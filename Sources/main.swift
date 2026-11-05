import AppKit
import UserNotifications
import UniformTypeIdentifiers

// MARK: - 数据模型

struct Lesson: Codable {
    var weekday: Int          // 1=周一 ... 7=周日
    var period: Int           // 0=早读/晚读，1..13=第N节
    var start: String         // "16:15"
    var end: String
    var klass: String
    var subject: String
    var weeks: String?        // "odd" 单周 / "even" 双周 / nil 每周
}

struct Timetable: Codable {
    var note: String?
    var leadMinutes: Int?
    var skipDates: [String]?
    var weekAnchor: String?
    var anchorIsOdd: Bool?
    var lessons: [Lesson]
}

// MARK: - 工具

let fm = FileManager.default
let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ClassReminder", isDirectory: true)
let tableURL = supportDir.appendingPathComponent("timetable.json")
let logURL = fm.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/ClassReminder.log")

func log(_ s: String) {
    let df = DateFormatter()
    df.dateFormat = "MM-dd HH:mm:ss"
    let line = "[\(df.string(from: Date()))] \(s)\n"
    if let d = line.data(using: .utf8) {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(d); try? h.close()
        } else {
            try? d.write(to: logURL)
        }
    }
}

func minutes(_ hm: String) -> Int? {
    let p = hm.split(separator: ":")
    guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
    return h * 60 + m
}

func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

func weekdayNumber(_ d: Date) -> Int {
    let wd = Calendar.current.component(.weekday, from: d)
    return wd == 1 ? 7 : wd - 1
}

func dateKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return "\(c.year!)-\(twoDigits(c.month!))-\(twoDigits(c.day!))"
}

func parseDate(_ s: String) -> Date? {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = .current
    return df.date(from: s)
}

func spoken(_ s: String) -> String {
    let map: [Character: String] = ["1": "一", "2": "二", "3": "三", "4": "四",
                                    "5": "五", "6": "六", "7": "七", "8": "八",
                                    "9": "九", "0": "零"]
    var out = ""
    for ch in s { out += map[ch] ?? String(ch) }
    return out
}

/// "11:25" → "11点25分"
func spokenTime(_ hm: String) -> String {
    let p = hm.split(separator: ":")
    guard p.count == 2 else { return hm }
    let h = Int(p[0]) ?? 0
    let m = Int(p[1]) ?? 0
    return m == 0 ? "\(h)点" : "\(h)点\(m)分"
}

func monthDay(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.month, .day], from: d)
    return "\(c.month!)月\(c.day!)日"
}

let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

// 配色
func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? dark : light
    }
}

enum Palette {
    static let accent = NSColor(srgbRed: 0.16, green: 0.42, blue: 0.94, alpha: 1)
    static let accent2 = NSColor(srgbRed: 0.35, green: 0.58, blue: 1.00, alpha: 1)
    static let amber = NSColor(srgbRed: 0.90, green: 0.55, blue: 0.05, alpha: 1)
    static let amber2 = NSColor(srgbRed: 0.98, green: 0.68, blue: 0.14, alpha: 1)

    static let todayCard = dyn(NSColor(srgbRed: 0.953, green: 0.965, blue: 0.984, alpha: 1),
                               NSColor(srgbRed: 0.145, green: 0.157, blue: 0.180, alpha: 1))
    static let tomorrowCard = dyn(NSColor(srgbRed: 1.000, green: 0.960, blue: 0.890, alpha: 1),
                                  NSColor(srgbRed: 0.220, green: 0.176, blue: 0.110, alpha: 1))
    static let tomorrowBorder = dyn(NSColor(srgbRed: 0.95, green: 0.72, blue: 0.30, alpha: 0.55),
                                    NSColor(srgbRed: 0.95, green: 0.72, blue: 0.30, alpha: 0.45))
    static let todayBorder = dyn(NSColor(srgbRed: 0.78, green: 0.83, blue: 0.92, alpha: 0.75),
                                 NSColor(srgbRed: 0.30, green: 0.34, blue: 0.42, alpha: 0.9))
}

// MARK: - 课表视图

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class Chip: FlippedView {
    var onTap: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onTap?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

final class ScheduleView: FlippedView {

    static let W: CGFloat = 384
    let pad: CGFloat = 16
    weak var owner: AppDelegate?

    init(owner: AppDelegate) {
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: ScheduleView.W, height: 600))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 小工具

    @discardableResult
    private func label(_ parent: NSView, _ s: String, _ font: NSFont, _ color: NSColor,
                       _ rect: NSRect, align: NSTextAlignment = .left) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = font
        t.textColor = color
        t.frame = rect
        t.alignment = align
        t.lineBreakMode = .byTruncatingTail
        t.isBezeled = false
        t.drawsBackground = false
        parent.addSubview(t)
        return t
    }

    private func card(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 12,
                      border: NSColor? = nil) -> FlippedView {
        let v = FlippedView(frame: rect)
        v.wantsLayer = true
        v.layer?.backgroundColor = color.cgColor
        v.layer?.cornerRadius = radius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        if let b = border {
            v.layer?.borderWidth = 1
            v.layer?.borderColor = b.cgColor
        }
        addSubview(v)
        return v
    }

    private func pill(_ parent: NSView, _ s: String, _ bg: NSColor, _ fg: NSColor,
                      rect: NSRect, fontSize: CGFloat = 11) -> NSView {
        let f = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let w = (s as NSString).size(withAttributes: [.font: f]).width.rounded(.up) + 16
        let v = FlippedView(frame: NSRect(x: rect.minX, y: rect.minY, width: w, height: rect.height))
        v.wantsLayer = true
        v.layer?.backgroundColor = bg.cgColor
        v.layer?.cornerRadius = rect.height / 2
        parent.addSubview(v)
        label(v, s, f, fg, NSRect(x: 0, y: (rect.height - 14) / 2, width: w, height: 14), align: .center)
        return v
    }

    private func footerButton(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat,
                              action: Selector) {
        let b = NSButton(frame: NSRect(x: x, y: y, width: w, height: 20))
        b.title = title
        b.isBordered = false
        b.bezelStyle = .inline
        b.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        b.contentTintColor = .secondaryLabelColor
        b.target = owner
        b.action = action
        b.alignment = .center
        addSubview(b)
    }

    // MARK: 构建

    private func build() {
        guard let owner = owner else { return }
        let now = Date()
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        var y: CGFloat = pad

        // ── 顶部：日期 + 周次
        label(self, weekdayNames[weekdayNumber(now)],
              .systemFont(ofSize: 20, weight: .bold), .labelColor,
              NSRect(x: pad, y: y - 4, width: 80, height: 26))
        label(self, monthDay(now), .systemFont(ofSize: 13, weight: .medium),
              .secondaryLabelColor, NSRect(x: pad + 62, y: y + 2, width: 90, height: 20))
        let isOdd = owner.isOddWeek(now)
        let pillW = pill(self, "第\(owner.weekIndex(now))周 · \(isOdd ? "单周" : "双周")",
                         isOdd ? Palette.accent : Palette.amber, .white,
                         rect: NSRect(x: 0, y: y + 1, width: 0, height: 20))
        pillW.frame.origin.x = ScheduleView.W - pad - pillW.frame.width
        y += 34

        // ── 下一节大卡
        let cardH: CGFloat = 108
        let nextCard = card(NSRect(x: pad, y: y, width: ScheduleView.W - pad * 2, height: cardH),
                            Palette.accent, radius: 14)
        if let g = CAGradientLayer() as CAGradientLayer? {
            g.frame = nextCard.bounds
            g.colors = [Palette.accent.cgColor, Palette.accent2.cgColor]
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.cornerRadius = 14
            g.cornerCurve = .continuous
            nextCard.layer?.insertSublayer(g, at: 0)
        }

        if let (l, date) = owner.nextLesson() {
            let sameDay = cal.isDateInToday(date)
            let isTmr = cal.isDateInTomorrow(date)
            let lead = owner.leadMinutes
            let where_ = sameDay ? "今天" : (isTmr ? "明天" : weekdayNames[weekdayNumber(date)])

            label(nextCard, "下一节 · \(where_)", .systemFont(ofSize: 11.5, weight: .semibold),
                  NSColor(white: 1, alpha: 0.8), NSRect(x: 18, y: 13, width: 200, height: 15))
            label(nextCard, l.start, .systemFont(ofSize: 40, weight: .heavy), .white,
                  NSRect(x: 16, y: 26, width: 190, height: 48))
            label(nextCard, "\(l.klass) · \(l.subject)", .systemFont(ofSize: 15, weight: .semibold),
                  NSColor(white: 1, alpha: 0.97), NSRect(x: 18, y: 74, width: 200, height: 20))

            let m = minutes(l.start) ?? 0
            let start = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: date) ?? date
            let minsLeft = Int(start.timeIntervalSince(now) / 60)
            let cd: String
            if minsLeft < 0 { cd = "进行中" }
            else if minsLeft >= 1440 { cd = "还有 \(minsLeft / 1440) 天" }
            else if minsLeft >= 60 {
                cd = minsLeft % 60 == 0 ? "还有 \(minsLeft / 60) 小时"
                                        : "还有 \(minsLeft / 60) 小时 \(minsLeft % 60) 分"
            } else { cd = "还有 \(minsLeft) 分钟" }

            label(nextCard, cd, .systemFont(ofSize: 15, weight: .bold),
                  NSColor(white: 1, alpha: 0.99),
                  NSRect(x: nextCard.frame.width - 178, y: 16, width: 160, height: 20), align: .right)
            let remindAt = max(0, m - lead)
            label(nextCard, "\(twoDigits(remindAt / 60)):\(twoDigits(remindAt % 60)) 提醒",
                  .systemFont(ofSize: 12, weight: .semibold),
                  NSColor(white: 1, alpha: 0.9),
                  NSRect(x: nextCard.frame.width - 178, y: 38, width: 160, height: 15), align: .right)
            let detail = l.period > 0 ? "\(l.start)–\(l.end) · 第\(l.period)节"
                                      : "\(l.start)–\(l.end)"
            label(nextCard, detail, .systemFont(ofSize: 11.5),
                  NSColor(white: 1, alpha: 0.75),
                  NSRect(x: nextCard.frame.width - 178, y: 74, width: 160, height: 15), align: .right)
        } else {
            label(nextCard, "最近都没课 🎉", .systemFont(ofSize: 17, weight: .bold), .white,
                  NSRect(x: 18, y: 42, width: 280, height: 24))
        }
        y += cardH + 20

        // ── 今天
        y = section(self, title: "今天", sub: "\(weekdayNames[weekdayNumber(now)]) · \(monthDay(now))",
                    lessons: owner.lessons(on: now), isToday: true,
                    cardColor: Palette.todayCard, border: Palette.todayBorder,
                    tint: Palette.accent, empty: "今天已经没课了", y: y, now: now)

        y += 18

        // ── 明天
        y = section(self, title: "明天", sub: "\(weekdayNames[weekdayNumber(tomorrow)]) · \(monthDay(tomorrow))",
                    lessons: owner.lessons(on: tomorrow), isToday: false,
                    cardColor: Palette.tomorrowCard, border: Palette.tomorrowBorder,
                    tint: Palette.amber, empty: "明天没课", y: y, now: now)

        y += 20

        // ── 课前提醒（可调）
        label(self, "课前提醒", .systemFont(ofSize: 12, weight: .semibold), .secondaryLabelColor,
              NSRect(x: pad, y: y + 5, width: 80, height: 18))
        let opts = [5, 10, 15, 20, 30]
        let chipW: CGFloat = 50, chipGap: CGFloat = 5, chipH: CGFloat = 26
        let chipStart = pad + 80
        let cur = owner.leadMinutes
        for (i, m) in opts.enumerated() {
            let r = NSRect(x: chipStart + (chipW + chipGap) * CGFloat(i), y: y, width: chipW, height: chipH)
            let sel = (m == cur)
            let chip = Chip(frame: r)
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 8
            chip.layer?.cornerCurve = .continuous
            chip.layer?.backgroundColor = sel ? Palette.accent.cgColor
                                             : NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
            if !sel {
                chip.layer?.borderWidth = 1
                chip.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.18).cgColor
            }
            let t = NSTextField(labelWithString: "\(m)分")
            t.font = .systemFont(ofSize: 12, weight: sel ? .bold : .medium)
            t.textColor = sel ? .white : .secondaryLabelColor
            t.alignment = .center
            t.frame = NSRect(x: 0, y: 5, width: chipW, height: 16)
            chip.addSubview(t)
            chip.onTap = { [weak owner] in owner?.setLead(m) }
            addSubview(chip)
        }
        y += chipH + 14

        // ── 底栏
        let hair = NSView(frame: NSRect(x: pad, y: y - 10, width: ScheduleView.W - pad * 2, height: 1))
        hair.wantsLayer = true
        hair.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        addSubview(hair)
        y += 10
        let items: [(String, Selector)] = [
            ("导入课表", #selector(AppDelegate.importTimetable)),
            ("下载模板", #selector(AppDelegate.exportTemplate)),
            ("测试提醒", #selector(AppDelegate.testAlert)),
            ("打开课表", #selector(AppDelegate.openTable)),
            ("切周次", #selector(AppDelegate.toggleWeek)),
            ("退出", #selector(AppDelegate.quit))
        ]
        let gap: CGFloat = 4
        let bw = (ScheduleView.W - pad * 2 - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
        for (i, it) in items.enumerated() {
            footerButton(it.0, x: pad + (bw + gap) * CGFloat(i), y: y, w: bw, action: it.1)
        }
        y += 20 + pad

        setFrameSize(NSSize(width: ScheduleView.W, height: y))
    }

    // MARK: 一天的区块

    private func section(_ host: NSView, title: String, sub: String, lessons: [Lesson],
                         isToday: Bool, cardColor: NSColor, border: NSColor, tint: NSColor,
                         empty: String, y: CGFloat, now: Date) -> CGFloat {
        var top = y

        let dot = FlippedView(frame: NSRect(x: pad, y: top + 6, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tint.cgColor
        dot.layer?.cornerRadius = 2
        host.addSubview(dot)

        label(host, title, .systemFont(ofSize: 15, weight: .heavy), .labelColor,
              NSRect(x: pad + 14, y: top, width: 60, height: 20))
        label(host, sub, .systemFont(ofSize: 12, weight: .medium), .secondaryLabelColor,
              NSRect(x: pad + 62, y: top + 2, width: 130, height: 17))
        if !lessons.isEmpty {
            label(host, "\(lessons.count) 节", .systemFont(ofSize: 11.5, weight: .medium),
                  .tertiaryLabelColor,
                  NSRect(x: ScheduleView.W - pad - 60, y: top + 2, width: 60, height: 16), align: .right)
        }
        top += 28

        let rowH: CGFloat = 40
        let h = lessons.isEmpty ? 48 : CGFloat(lessons.count) * rowH + 12
        let c = card(NSRect(x: pad, y: top, width: ScheduleView.W - pad * 2, height: h),
                     cardColor, radius: 12, border: border)
        host.addSubview(c)
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 4, height: h))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = tint.withAlphaComponent(0.85).cgColor
        c.addSubview(bar)

        guard !lessons.isEmpty else {
            label(c, empty, .systemFont(ofSize: 13, weight: .medium), .secondaryLabelColor,
                  NSRect(x: 16, y: 15, width: c.frame.width - 32, height: 18))
            return top + h
        }

        let nowMin = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)

        for (i, l) in lessons.enumerated() {
            let ry = 6 + CGFloat(i) * rowH
            let s = minutes(l.start) ?? 0
            let e = minutes(l.end) ?? 0
            let isPast = isToday && e <= nowMin
            let isNow = isToday && s <= nowMin && nowMin < e
            let alpha: CGFloat = isPast ? 0.42 : 1.0

            if isNow {
                let hl = FlippedView(frame: NSRect(x: 8, y: ry - 2, width: c.frame.width - 16, height: rowH - 2))
                hl.wantsLayer = true
                hl.layer?.backgroundColor = tint.withAlphaComponent(0.13).cgColor
                hl.layer?.cornerRadius = 8
                c.addSubview(hl)
            }

            if i > 0 {
                let sep = NSView(frame: NSRect(x: 20, y: ry - 2, width: c.frame.width - 40, height: 1))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = border.withAlphaComponent(0.55).cgColor
                c.addSubview(sep)
            }

            let t = label(c, "\(l.start)–\(l.end)",
                          .monospacedDigitSystemFont(ofSize: 13, weight: isNow ? .bold : .medium),
                          .labelColor.withAlphaComponent(alpha),
                          NSRect(x: 20, y: ry + 11, width: 100, height: 18))
            t.lineBreakMode = .byClipping

            label(c, l.klass, .systemFont(ofSize: 14, weight: isNow ? .bold : .semibold),
                  tint.withAlphaComponent(isPast ? 0.75 : 1), NSRect(x: 122, y: ry + 11, width: 80, height: 18))
            label(c, l.subject, .systemFont(ofSize: 11.5), .secondaryLabelColor.withAlphaComponent(alpha),
                  NSRect(x: 204, y: ry + 12, width: 76, height: 17))

            if isNow {
                label(c, "进行中", .systemFont(ofSize: 10.5, weight: .bold), tint,
                      NSRect(x: c.frame.width - 74, y: ry + 12, width: 58, height: 16), align: .right)
            } else if isPast {
                label(c, "✓", .systemFont(ofSize: 12, weight: .semibold), .tertiaryLabelColor,
                      NSRect(x: c.frame.width - 74, y: ry + 11, width: 58, height: 16), align: .right)
            } else if l.period > 0 {
                label(c, "第\(l.period)节", .systemFont(ofSize: 10.5, weight: .medium),
                      .tertiaryLabelColor,
                      NSRect(x: c.frame.width - 74, y: ry + 12, width: 58, height: 16), align: .right)
            }
        }
        return top + h
    }
}


// MARK: - 课表导入 / 模板

struct CSVError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

enum TimetableIO {

    static let template = """
    星期,节次,开始时间,结束时间,班级,科目,周次
    周一,第3节,09:25,10:05,九1班,历史,每周
    周二,第4节,10:30,11:10,九3班,历史,单周
    周二,第4节,10:30,11:10,九3班,历史,双周
    周五,早读,07:30,07:50,七1/八2班,历史早读,单周
    """

    /// 写模板（带 BOM，Excel 打开中文不乱码）
    static func writeTemplate(to url: URL) throws {
        let text = "\u{FEFF}" + template.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        try text.data(using: .utf8)!.write(to: url)
    }

    static func decode(_ data: Data) -> String? {
        if var s = String(data: data, encoding: .utf8) {
            if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
            return s
        }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let s = String(data: data, encoding: gb) { return s }
        return nil
    }

    static func splitRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\""); i = next
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    row.append(field); field = ""
                } else if ch.isNewline {
                    row.append(field); field = ""; rows.append(row); row = []
                } else {
                    field.append(ch)
                }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    static func columnKey(_ h: String) -> String? {
        let t = h.trimmingCharacters(in: .whitespaces).lowercased()
        if t.contains("星期") || t.contains("weekday") { return "weekday" }
        if t.contains("节次") || t.contains("period") { return "period" }
        if t.contains("开始") || t.contains("start") { return "start" }
        if t.contains("结束") || t.contains("end") { return "end" }
        if t.contains("班级") || t.contains("class") { return "klass" }
        if t.contains("科目") || t.contains("课程") || t.contains("subject") { return "subject" }
        if t.contains("周次") || t.contains("week") { return "weeks" }
        return nil
    }

    static func weekday(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let n = Int(t), (1...7).contains(n) { return n }
        let cn: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
        if let last = t.last, let v = cn[String(last)] { return v }
        let en = ["mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7]
        let low = t.lowercased()
        for (k, v) in en where low.hasPrefix(k) { return v }
        return nil
    }

    static func period(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("早读") || t.contains("晚读") || t.contains("早自习") { return 0 }
        if t.contains("晚自习") || t.contains("晚修") { return 11 }
        let digits = t.filter { $0.isNumber }
        if let n = Int(digits), (0...13).contains(n) { return n }
        return nil
    }

    static func time(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "点", with: ":")
            .replacingOccurrences(of: "分", with: "")
        var h = 0, m = 0
        if t.contains(":") {
            let p = t.split(separator: ":")
            guard p.count >= 2, let hh = Int(p[0]), let mm = Int(p[1]),
                  (0...23).contains(hh), (0...59).contains(mm) else { return nil }
            h = hh; m = mm
        } else {
            let d = t.filter { $0.isNumber }
            if d.count == 3 { h = Int(d.prefix(1))!; m = Int(d.suffix(2))! }
            else if d.count == 4 { h = Int(d.prefix(2))!; m = Int(d.suffix(2))! }
            else { return nil }
            if h > 23 || m > 59 { return nil }
        }
        return String(format: "%02d:%02d", h, m)
    }

    static func weeks(_ s: String) -> [String?] {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("单双") || t.lowercased().contains("both") { return ["odd", "even"] }
        if t.contains("单") || t.lowercased() == "odd" { return ["odd"] }
        if t.contains("双") || t.lowercased() == "even" { return ["even"] }
        return [nil]
    }

    /// 返回 (课程, 错误)
    static func parse(url: URL) throws -> [Lesson] {
        guard let data = try? Data(contentsOf: url) else {
            throw CSVError(msg: "读不到这个文件：\(url.lastPathComponent)")
        }
        guard let raw = decode(data) else {
            throw CSVError(msg: "文件编码看不懂，请用 Excel／Numbers 另存为 UTF-8 的 CSV")
        }
        let rows = splitRows(raw)
        guard !rows.isEmpty else { throw CSVError(msg: "文件是空的") }

        var idx: [String: Int] = [:]
        var start = 0
        if rows[0].contains(where: { columnKey($0) != nil }) {
            for (i, h) in rows[0].enumerated() {
                if let k = columnKey(h) { idx[k] = i }
            }
            start = 1
        } else {
            idx = ["weekday": 0, "period": 1, "start": 2, "end": 3, "klass": 4, "subject": 5, "weeks": 6]
        }
        guard let _ = idx["weekday"], let _ = idx["klass"] else {
            throw CSVError(msg: "缺少必需列。模板表头是：星期,节次,开始时间,结束时间,班级,科目,周次")
        }

        var lessons: [Lesson] = []
        var problems: [String] = []

        for (n, row) in rows.enumerated() where n >= start {
            let line = n + 1
            func cell(_ k: String) -> String {
                guard let i = idx[k], i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespaces)
            }
            if cell("weekday").isEmpty && cell("klass").isEmpty { continue }

            guard let wd = weekday(cell("weekday")) else {
                problems.append("第 \(line) 行：星期「\(cell("weekday"))」看不懂（写周一~周日，或 1~7）")
                continue
            }
            guard let pd = period(cell("period")) else {
                problems.append("第 \(line) 行：节次「\(cell("period"))」看不懂（写第5节 / 5 / 早读 / 晚读）")
                continue
            }
            guard let st = time(cell("start")), let et = time(cell("end")) else {
                problems.append("第 \(line) 行：时间「\(cell("start"))–\(cell("end"))」看不懂（写成 07:50）")
                continue
            }
            if (minutes(st) ?? 0) >= (minutes(et) ?? 0) {
                problems.append("第 \(line) 行：开始时间比结束时间晚")
                continue
            }
            let klass = cell("klass")
            let subject = cell("subject").isEmpty ? "课" : cell("subject")
            if klass.isEmpty {
                problems.append("第 \(line) 行：班级是空的")
                continue
            }
            for w in weeks(cell("weeks")) where true {
                lessons.append(Lesson(weekday: wd, period: pd, start: st, end: et,
                                      klass: klass, subject: subject, weeks: w))
            }
        }

        guard problems.isEmpty else {
            let head = problems.prefix(6).joined(separator: "\n")
            let more = problems.count > 6 ? "\n……还有 \(problems.count - 6) 处" : ""
            throw CSVError(msg: head + more)
        }
        guard !lessons.isEmpty else { throw CSVError(msg: "一行有效的课都没读到") }
        return lessons
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    var statusItem: NSStatusItem!
    var popover: NSPopover?
    var timer: Timer?
    var table = Timetable(note: nil, leadMinutes: 10, skipDates: [],
                          weekAnchor: nil, anchorIsOdd: true, lessons: [])
    var alertPanel: NSPanel?
    var notificationsAllowed = false
    var lastTitleLogged = ""
    var lastTableMTime: Date?

    let firedKey = "firedReminders"
    let offsetKey = "weekOffset"
    let leadKey = "leadMinutes"

    /// 提前多少分钟提醒：界面里调的优先，其次课表 JSON，最后 10
    var leadMinutes: Int {
        let u = UserDefaults.standard.integer(forKey: leadKey)
        if u > 0 { return u }
        return table.leadMinutes ?? 10
    }

    func setLead(_ m: Int) {
        UserDefaults.standard.set(m, forKey: leadKey)
        UserDefaults.standard.removeObject(forKey: firedKey)
        log("提前提醒改为 \(m) 分钟")
        tick()
        refreshPopover()
    }

    // MARK: 启动

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        seedIfNeeded()
        loadTable()

        if let i = CommandLine.arguments.firstIndex(of: "--parse"),
           i + 1 < CommandLine.arguments.count {
            do {
                let ls = try TimetableIO.parse(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                print("OK \(ls.count) 节课")
                for l in ls {
                    let w = l.weeks == "odd" ? "单周" : (l.weeks == "even" ? "双周" : "每周")
                    print("  周\(l.weekday) 第\(l.period)节 \(l.start)-(\(l.end)) \(l.klass) \(l.subject) [\(w)]")
                }
            } catch {
                print("ERR \(error.localizedDescription)")
            }
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--import"),
           i + 1 < CommandLine.arguments.count {
            do {
                let ls = try TimetableIO.parse(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                applyLessons(ls)
                print("导入成功：\(ls.count) 条，已写入 \(tableURL.path)")
            } catch {
                print("导入失败：\(error.localizedDescription)")
            }
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--template"),
           i + 1 < CommandLine.arguments.count {
            do {
                try TimetableIO.writeTemplate(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                print("模板已写到 \(CommandLine.arguments[i + 1])")
            } catch { print("ERR \(error.localizedDescription)") }
            exit(0)
        }

        if CommandLine.arguments.contains("--dump") {
            let cal = Calendar.current
            for i in 0...7 {
                let d = cal.date(byAdding: .day, value: i, to: Date())!
                let parts = lessons(on: d).map { "\($0.start)-\($0.end) \($0.klass) \($0.subject)" }
                print("\(dateKey(d)) \(weekdayNames[weekdayNumber(d)]) \(weekLabel(d)) | " +
                      (parts.isEmpty ? "—" : parts.joined(separator: " ; ")))
            }
            fflush(stdout)
            exit(0)
        }

        if CommandLine.arguments.contains("--voice") {
            print("zhVoice = \(zhVoice ?? "nil")")
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            var a: [String] = []
            if let v = zhVoice { a += ["-v", v] }
            a += ["-o", "/tmp/voice_probe.aiff", "九三班历史课，还有15分钟"]
            probe.arguments = a
            try? probe.run()
            probe.waitUntilExit()
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--shotbar"),
           i + 1 < CommandLine.arguments.count {
            renderStatusBar(to: CommandLine.arguments[i + 1])
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--shotstart"),
           i + 1 < CommandLine.arguments.count {
            let root = alertRoot(size: NSSize(width: 620, height: 254),
                                 headline: "九3班 · 历史",
                                 startTime: "11:25",
                                 sub: "12:05 下课",
                                 detail: "第5节", tone: .start)
            dumpView(root, to: CommandLine.arguments[i + 1])
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--shotalert"),
           i + 1 < CommandLine.arguments.count {
            let root = alertRoot(size: NSSize(width: 620, height: 254),
                                 headline: "九3班 · 历史",
                                 startTime: "11:25",
                                 sub: "还有 15 分钟",
                                 detail: "第5节")
            dumpView(root, to: CommandLine.arguments[i + 1])
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--shot"),
           i + 1 < CommandLine.arguments.count {
            renderShot(to: CommandLine.arguments[i + 1])
            exit(0)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            b.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "上课提醒")
            b.image?.isTemplate = true
            b.imagePosition = .imageLeading
            b.imageScaling = .scaleProportionallyDown
            b.target = self
            b.action = #selector(togglePopover)
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        popover = pop

        requestNotificationAuth()

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tick() }

        tick()
        log("启动完成：\(table.lessons.count) 条课程 · 今天是\(weekLabel(Date()))")

        if CommandLine.arguments.contains("--pop") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.togglePopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { NSApp.terminate(nil) }
        }

        if CommandLine.arguments.contains("--teststart") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let (l, _) = self.nextLesson() {
                    self.push(headline: "\(l.klass) · \(l.subject)", startTime: l.start,
                              sub: "\(l.end) 下课",
                              detail: l.period > 0 ? "第\(l.period)节" : "",
                              speech: nil, chimes: 1, tone: .start)
                }
                log("测试：到点提醒")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { NSApp.terminate(nil) }
        }

        if CommandLine.arguments.contains("--test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.testAlert()
                log("已发送测试提醒")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { NSApp.terminate(nil) }
        }
    }

    func dumpView(_ v: NSView, to path: String, scale: CGFloat = 2) {
        let size = v.frame.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = v
        v.layoutSubtreeIfNeeded()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            v.cacheDisplay(in: v.bounds, to: rep)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("shot -> \(path) \(size)")
        }
    }

    func renderShot(to path: String) {
        let v = ScheduleView(owner: self)
        let size = v.frame.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = v
        v.layoutSubtreeIfNeeded()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            v.cacheDisplay(in: v.bounds, to: rep)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("shot -> \(path) \(size)")
        }
    }

    func seedIfNeeded() {
        guard !fm.fileExists(atPath: tableURL.path) else { return }
        if let src = Bundle.main.url(forResource: "timetable", withExtension: "json"),
           let data = try? Data(contentsOf: src) {
            try? data.write(to: tableURL)
            log("已写入默认课表")
        }
    }

    func loadTable() {
        guard let data = try? Data(contentsOf: tableURL),
              let t = try? JSONDecoder().decode(Timetable.self, from: data) else {
            log("课表读取失败：\(tableURL.path)")
            return
        }
        table = t
        lastTableMTime = (try? fm.attributesOfItem(atPath: tableURL.path))?[.modificationDate] as? Date
        updateStatusTitle()
    }

    func poll() {
        if let m = (try? fm.attributesOfItem(atPath: tableURL.path))?[.modificationDate] as? Date,
           m != lastTableMTime {
            loadTable()
            log("课表文件有改动，已重新载入")
        }
        tick()
    }

    // MARK: 通知

    func requestNotificationAuth() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] ok, err in
            self?.notificationsAllowed = ok
            log("通知授权=\(ok) err=\(err?.localizedDescription ?? "nil")")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: 提醒：大卡片 + 连响 + 语音

    var alertSeq = 0

    /// 挑一个中文女声：Tingting 最稳，其次 Flo / Sandy / Shelley / Grandma / Meijia / Sinji
    lazy var zhVoice: String? = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "?"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""

        var voices: [(name: String, locale: String)] = []
        for line in out.split(separator: "\n") {
            guard let r = line.range(of: "zh_") else { continue }
            let name = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let rest = line[r.lowerBound...]
            let locale = rest.split(separator: " ").first.map(String.init) ?? "zh_CN"
            if !name.isEmpty { voices.append((name, locale)) }
        }

        let female = ["Tingting", "Flo", "Sandy", "Shelley", "Grandma", "Meijia", "Sinji"]
        for want in female {
            for loc in ["zh_CN", "zh_TW", "zh_HK"] {
                if let v = voices.first(where: {
                    $0.name.lowercased().hasPrefix(want.lowercased()) && $0.locale == loc
                }) { return v.name }
            }
        }
        return voices.first?.name
    }()

    func playChime(loud: Bool = true) {
        for name in ["Sosumi", "Hero", "Glass", "Ping"] {
            if let snd = NSSound(named: name) {
                snd.volume = 1.0
                snd.play()
                if loud { NSSound.beep() }
                return
            }
        }
        NSSound.beep()
    }

    func speak(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args: [String] = []
        if let v = zhVoice { args += ["-v", v] }
        args += ["-r", "175", text]
        p.arguments = args
        try? p.run()
    }

    enum Tone { case lead, start }

    func push(headline: String, startTime: String, sub: String, detail: String,
              speech: String? = nil, chimes: Int = 3, tone: Tone = .lead) {
        showPanel(headline: headline, startTime: startTime, sub: sub, detail: detail,
                  speech: speech, chimes: chimes, tone: tone)

        guard notificationsAllowed else { return }
        let content = UNMutableNotificationContent()
        content.title = speech ?? headline
        content.body = "\(sub) · \(detail)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err = err { log("通知失败：\(err.localizedDescription)") }
        }
    }

    func alertRoot(size: NSSize, headline: String, startTime: String,
                   sub: String, detail: String, tone: Tone = .lead) -> FlippedView {
        let w = size.width, h = size.height
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        root.layer?.cornerRadius = 24
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        let c1 = tone == .lead ? Palette.accent : Palette.amber
        let c2 = tone == .lead ? Palette.accent2 : Palette.amber2
        root.layer?.backgroundColor = c1.cgColor
        if let g = CAGradientLayer() as CAGradientLayer? {
            g.frame = root.bounds
            g.colors = [c1.cgColor, c2.cgColor]
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint = CGPoint(x: 1, y: 1)
            root.layer?.insertSublayer(g, at: 0)
        }
        func label(_ text: String, _ font: NSFont, _ color: NSColor, _ rect: NSRect,
                   align: NSTextAlignment = .left) {
            let t = NSTextField(labelWithString: text)
            t.font = font
            t.textColor = color
            t.frame = rect
            t.alignment = align
            t.isBezeled = false
            t.drawsBackground = false
            root.addSubview(t)
        }
        let kicker = tone == .lead ? "即将上课" : "现在上课"
        let topText = detail.isEmpty ? kicker : "\(kicker) · \(detail)"
        label(topText, .systemFont(ofSize: 16, weight: .bold),
              NSColor(white: 1, alpha: 0.75), NSRect(x: 40, y: 24, width: 400, height: 22))
        label(headline, .systemFont(ofSize: 42, weight: .heavy), .white,
              NSRect(x: 36, y: 40, width: w - 72, height: 54))

        // 上课时间：最大号
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 54, weight: .heavy)
        let unitFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let timeAttr = NSMutableAttributedString(string: startTime, attributes: [
            .font: timeFont, .foregroundColor: NSColor.white
        ])
        timeAttr.append(NSAttributedString(string: " 上课", attributes: [
            .font: unitFont,
            .foregroundColor: NSColor(white: 1, alpha: 0.82),
            .baselineOffset: 9
        ]))
        let timeLabel = NSTextField(labelWithAttributedString: timeAttr)
        timeLabel.frame = NSRect(x: 36, y: 96, width: 300, height: 66)
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        root.addSubview(timeLabel)

        label(sub, .systemFont(ofSize: 22, weight: .bold),
              NSColor(white: 1, alpha: 0.98),
              NSRect(x: w - 258, y: 118, width: 220, height: 30), align: .right)

        let btn = NSButton(frame: NSRect(x: w - 176, y: h - 72, width: 140, height: 46))
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.white.cgColor
        btn.layer?.cornerRadius = 14
        btn.layer?.cornerCurve = .continuous
        btn.attributedTitle = NSAttributedString(
            string: "知道了",
            attributes: [.foregroundColor: Palette.accent,
                         .font: NSFont.systemFont(ofSize: 16, weight: .bold)])
        btn.target = self
        btn.action = #selector(dismissAlert)
        root.addSubview(btn)
        return root
    }

    func showPanel(headline: String, startTime: String, sub: String, detail: String,
                   speech: String?, chimes: Int = 3, tone: Tone = .lead) {
        alertPanel?.close()
        alertSeq += 1
        let seq = alertSeq

        let w: CGFloat = 620, h: CGFloat = 254
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = alertRoot(size: NSSize(width: w, height: h), headline: headline,
                             startTime: startTime, sub: sub, detail: detail, tone: tone)
        panel.contentView = root
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - w - 40, y: f.maxY - h - 40))
        }
        panel.orderFrontRegardless()
        alertPanel = panel

        // 连响三遍 + 语音播报
        NSSound.beep()
        for i in 0..<chimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 2.2) { [weak self] in
                guard let self = self, self.alertSeq == seq else { return }
                self.playChime()
            }
        }
        if let sp = speech {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.alertSeq == seq else { return }
                self.speak(sp)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in
                guard let self = self, self.alertSeq == seq else { return }
                self.speak(sp)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self, weak panel] in
            guard let self = self, self.alertSeq == seq else { return }
            panel?.close()
            _ = self
        }
    }

    @objc func dismissAlert() {
        alertSeq += 1
        alertPanel?.close()
        alertPanel = nil
    }

    // MARK: 单双周

    func weekIndex(_ d: Date) -> Int {
        let cal = Calendar.current
        guard let anchorRaw = parseDate(table.weekAnchor ?? "2026-08-31") else { return 1 }
        let anchor = cal.startOfDay(for: anchorRaw)
        let anchorMonday = cal.date(byAdding: .day,
                                    value: -(weekdayNumber(anchor) - 1), to: anchor)!
        let day = cal.startOfDay(for: d)
        let monday = cal.date(byAdding: .day, value: -(weekdayNumber(day) - 1), to: day)!
        let days = cal.dateComponents([.day], from: anchorMonday, to: monday).day ?? 0
        return Int(floor(Double(days) / 7.0)) + 1
    }

    func isOddWeek(_ d: Date) -> Bool {
        let offset = UserDefaults.standard.integer(forKey: offsetKey)
        let base = (weekIndex(d) + offset) % 2 == 1
        return (table.anchorIsOdd ?? true) ? base : !base
    }

    func weekLabel(_ d: Date) -> String {
        "第\(weekIndex(d))周·\(isOddWeek(d) ? "单周" : "双周")"
    }

    func matches(_ l: Lesson, _ d: Date) -> Bool {
        guard let w = l.weeks, w != "all" else { return true }
        return (w == "odd") == isOddWeek(d)
    }

    func lessons(on d: Date) -> [Lesson] {
        let wd = weekdayNumber(d)
        return table.lessons
            .filter { $0.weekday == wd && matches($0, d) }
            .sorted { ($0.start) < ($1.start) }
    }

    func isSkipped(_ d: Date) -> Bool {
        (table.skipDates ?? []).contains(dateKey(d))
    }

    func nextLesson() -> (Lesson, Date)? {
        let now = Date()
        for offset in 0...7 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: now) else { continue }
            if isSkipped(day) { continue }
            for l in lessons(on: day) {
                guard let m = minutes(l.start) else { continue }
                guard let start = Calendar.current.date(bySettingHour: m / 60, minute: m % 60,
                                                        second: 0, of: day) else { continue }
                if start > now.addingTimeInterval(30) { return (l, start) }
            }
        }
        return nil
    }

    func tick() {
        let now = Date()
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let key = dateKey(now)
        let lead = leadMinutes

        var fired = UserDefaults.standard.stringArray(forKey: firedKey) ?? []

        if !isSkipped(now) {
            for l in lessons(on: now) {
                guard let startMin = minutes(l.start) else { continue }
                let head = "\(l.klass) · \(l.subject)"
                let detail = l.period > 0 ? "第\(l.period)节" : ""
                let leadAt = startMin - lead

                // ① 提前 N 分钟：大卡片 + 三连响 + 语音
                let leadId = "\(key)#\(l.period)#\(l.klass)#lead"
                if nowMin >= leadAt && nowMin < startMin && !fired.contains(leadId) {
                    let remain = startMin - nowMin
                    let sub = remain >= 2 ? "还有 \(remain) 分钟" : "马上就该上课了"
                    let speech = "\(spoken(l.klass))\(l.subject)课，\(spokenTime(l.start))上课，还有\(remain)分钟"
                    push(headline: head, startTime: l.start, sub: sub, detail: detail,
                         speech: speech, chimes: 3, tone: .lead)
                    log("提前提醒：\(head) · \(sub)")
                    fired.append(leadId)
                }

                // ② 到点：再提醒一次，不语音，只响一声
                let startId = "\(key)#\(l.period)#\(l.klass)#start"
                if nowMin >= startMin && nowMin < startMin + 2 && !fired.contains(startId) {
                    push(headline: head, startTime: l.start, sub: "\(l.end) 下课", detail: detail,
                         speech: nil, chimes: 1, tone: .start)
                    log("到点提醒：\(head) · 第\(l.period)节")
                    fired.append(startId)
                }
            }
        }

        UserDefaults.standard.set(fired.filter { $0.hasPrefix(key) }, forKey: firedKey)
        updateStatusTitle()
    }

    func statusBarTitle() -> String {
        guard let (l, date) = nextLesson() else { return " 无课" }
        let tag = Calendar.current.isDateInToday(date) ? "" : "\(weekdayNames[weekdayNumber(date)]) "
        return " \(tag)\(l.start) \(l.klass)"
    }

    func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        button.title = statusBarTitle()
        if let (l, _) = nextLesson() {
            button.toolTip = "下一节：\(l.klass) \(l.subject) \(l.start)–\(l.end)"
        }
        if lastTitleLogged != button.title {
            lastTitleLogged = button.title
            log("菜单栏显示：\(button.title)")
        }
    }

    /// 画一张菜单栏示意图（真截图需要屏幕录制权限）
    func renderStatusBar(to path: String) {
        let w: CGFloat = 252, h: CGFloat = 44
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        let barColor = dyn(NSColor(srgbRed: 0.965, green: 0.965, blue: 0.973, alpha: 1),
                           NSColor(srgbRed: 0.145, green: 0.145, blue: 0.157, alpha: 1))
        root.layer?.backgroundColor = barColor.cgColor

        let icon = NSImageView(frame: NSRect(x: w - 168, y: 13, width: 17, height: 17))
        icon.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        root.addSubview(icon)

        let t = NSTextField(labelWithString: statusBarTitle().trimmingCharacters(in: .whitespaces))
        t.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        t.textColor = .labelColor
        t.frame = NSRect(x: w - 146, y: 12, width: 140, height: 18)
        root.addSubview(t)

        let sep = NSView(frame: NSRect(x: w - 6, y: 8, width: 1, height: h - 16))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        root.addSubview(sep)

        dumpView(root, to: path)
    }

    // MARK: 弹窗

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        let v = ScheduleView(owner: self)
        let vc = NSViewController()
        vc.view = v
        popover?.contentViewController = vc
        popover?.contentSize = v.frame.size
        NSApp.activate(ignoringOtherApps: true)
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover?.contentViewController?.view.window?.makeKey()
    }

    @objc func toggleWeek() {
        let cur = UserDefaults.standard.integer(forKey: offsetKey)
        UserDefaults.standard.set(cur == 0 ? 1 : 0, forKey: offsetKey)
        UserDefaults.standard.removeObject(forKey: firedKey)
        log("手动切换周次 → \(isOddWeek(Date()) ? "单周" : "双周")")
        tick()
        refreshPopover()
    }

    func refreshPopover() {
        guard popover?.isShown == true else { return }
        let v = ScheduleView(owner: self)
        popover?.contentViewController?.view = v
        popover?.contentSize = v.frame.size
    }

    // MARK: 导入 / 模板

    func alertOK(_ title: String, _ info: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func applyLessons(_ lessons: [Lesson]) {
        var t = table
        t.lessons = lessons
        applyTimetable(t)
    }

    func applyTimetable(_ t: Timetable) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(t) { try? data.write(to: tableURL) }
        loadTable()
        tick()
        refreshPopover()
        log("导入课表：\(t.lessons.count) 条")
    }

    @objc func importTimetable() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选你填好的课表（CSV 模板，或本 App 导出的 timetable.json）"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if url.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: url),
               let t = try? JSONDecoder().decode(Timetable.self, from: data) {
                applyTimetable(t)
                alertOK("导入成功", "读到 \(t.lessons.count) 条课程。")
            } else {
                alertOK("导入失败", "这个 JSON 不是本 App 的课表格式。")
            }
            return
        }

        do {
            let lessons = try TimetableIO.parse(url: url)
            applyLessons(lessons)
            alertOK("导入成功", "读到 \(lessons.count) 条课程，菜单栏和提醒已按新课表运行。")
        } catch {
            alertOK("导入失败", error.localizedDescription)
        }
    }

    @objc func exportTemplate() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "课表模板.csv"
        panel.message = "保存空白模板，用 Excel / Numbers 填好，再点「导入课表」"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TimetableIO.writeTemplate(to: url)
            alertOK("模板已保存", url.path)
        } catch {
            alertOK("保存失败", error.localizedDescription)
        }
    }

    @objc func openTable() { NSWorkspace.shared.open(tableURL) }

    @objc func reloadTable() {
        loadTable(); tick(); log("手动重新载入课表"); refreshPopover()
    }

    @objc func testAlert() {
        // 连续演示两次：先「提前」，15 秒后「到点」
        let l = nextLesson()?.0 ?? Lesson(weekday: 4, period: 5, start: "11:25", end: "12:05",
                                          klass: "九3班", subject: "历史", weeks: nil)
        let detail = l.period > 0 ? "第\(l.period)节" : ""

        push(headline: "\(l.klass) · \(l.subject)", startTime: l.start,
             sub: "还有 \(leadMinutes) 分钟（测试）", detail: detail,
             speech: "\(spoken(l.klass))\(l.subject)课，\(spokenTime(l.start))上课，还有\(leadMinutes)分钟",
             chimes: 3, tone: .lead)

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.push(headline: "\(l.klass) · \(l.subject)", startTime: l.start,
                       sub: "\(l.end) 下课", detail: detail,
                       speech: nil, chimes: 1, tone: .start)
            log("测试：到点提醒")
        }
    }

    @objc func quit() {
        LoginItem.shell("/bin/launchctl", ["bootout", "gui/\(getuid())", LoginItem.plistURL.path])
        NSApp.terminate(nil)
    }
}

// MARK: - 开机自启

enum LoginItem {
    static let label = "com.mac.classreminder"
    static var plistURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var plistExists: Bool { fm.fileExists(atPath: plistURL.path) }

    @discardableResult
    static func shell(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
