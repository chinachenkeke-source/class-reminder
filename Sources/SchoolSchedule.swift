import AppKit
import UniformTypeIdentifiers

// 查询数据与个人提醒数据完全独立。
struct SchoolLesson: Codable {
    var klass: String
    var weekday: Int
    var period: String
    var start: String
    var end: String
    var subject: String
    var teacher: String
    var weeks: String?
}

struct SchoolTimetable: Codable {
    var effectiveFrom: String
    var classes: [String]
    var lessons: [SchoolLesson]
}

final class SchoolStore {
    let url = supportDir.appendingPathComponent("school-timetable.json")
    var data: SchoolTimetable?
    var selectedClass = UserDefaults.standard.string(forKey: "schoolSelectedClass") ?? "七1班"

    func load() {
        let source = fm.fileExists(atPath: url.path) ? url : Bundle.main.url(forResource: "school-timetable", withExtension: "json")
        if let source, let bytes = try? Data(contentsOf: source),
           let decoded = try? JSONDecoder().decode(SchoolTimetable.self, from: bytes) {
            data = decoded
            if !decoded.classes.contains(selectedClass) { selectedClass = decoded.classes.first ?? "" }
        }
    }

    static func encode(_ data: SchoolTimetable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(data)
    }

    func save(_ value: SchoolTimetable) throws {
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Self.encode(value).write(to: url, options: .atomic)
        load()
    }
}

enum SchoolIO {
    static let subjects = ["信息技术", "道德与法治", "政治", "道法", "历史", "生物", "地理", "语文", "数学", "英语", "物理", "化学", "体育", "音乐", "美术", "班会", "劳动", "体健"]

    static func className(_ text: String) -> String {
        text.replacingOccurrences(of: "年级", with: "").filter { !$0.isWhitespace }
    }

    static func course(_ text: String) -> (String, String) {
        let clean = text.replacingOccurrences(of: "（单周）", with: "")
            .replacingOccurrences(of: "（双周）", with: "").filter { !$0.isWhitespace }
        // 原表同时有「科目+教师」和「教师+科目」，部分单元格没有换行。
        if let re = try? NSRegularExpression(pattern: "^(?:" + subjects.joined(separator: "|") + ")(?:/(?:" + subjects.joined(separator: "|") + "))*"),
           let match = re.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            let subject = (clean as NSString).substring(with: match.range)
            return (subject, String(clean.dropFirst(subject.count)))
        }
        if let subject = subjects.first(where: { clean.hasSuffix($0) }) {
            return (subject, String(clean.dropLast(subject.count)))
        }
        return (clean, "")
    }

    static func parse(_ url: URL) throws -> SchoolTimetable {
        let rows = try TimetableIO.xlsxRows(url: url, sheetName: "班级总课表")
        let reading = try TimetableIO.xlsxRows(url: url, sheetName: "早晚读")
        func cell(_ rows: [[String]], _ r: Int, _ c: Int) -> String {
            guard r < rows.count, c < rows[r].count else { return "" }
            return rows[r][c].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard rows.count >= 4 else { throw CSVError(msg: "班级总课表没有课程数据") }
        let title = cell(rows, 0, 0)
        let re = try NSRegularExpression(pattern: "(20[0-9]{2})年.*?([0-9]{1,2})[.月]([0-9]{1,2})")
        guard let m = re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let year = Int((title as NSString).substring(with: m.range(at: 1))),
              let month = Int((title as NSString).substring(with: m.range(at: 2))),
              let day = Int((title as NSString).substring(with: m.range(at: 3))),
              (1...12).contains(month), (1...31).contains(day) else {
            throw CSVError(msg: "总课表标题需要包含生效日期，例如：2026年秋季学期班级总课表11.25")
        }
        var result = SchoolTimetable(effectiveFrom: String(format: "%04d-%02d-%02d", year, month, day), classes: [], lessons: [])
        let timeRE = try NSRegularExpression(pattern: "([0-9]+)\\s+([0-9]{1,2}:[0-9]{2})[-–]([0-9]{1,2}:[0-9]{2})")
        for r in 3..<rows.count {
            let klass = className(cell(rows, r, 0))
            guard klass.hasSuffix("班"), !klass.isEmpty else { continue }
            result.classes.append(klass)
            var weekday = 0
            for c in 1..<max(rows[1].count, rows[2].count) {
                if let d = TimetableIO.weekday(cell(rows, 1, c)) { weekday = d }
                let header = cell(rows, 2, c)
                let text = cell(rows, r, c)
                guard weekday > 0, !text.isEmpty,
                      let t = timeRE.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else { continue }
                func part(_ n: Int) -> String { (header as NSString).substring(with: t.range(at: n)) }
                guard let start = TimetableIO.time(part(2)), let end = TimetableIO.time(part(3)), start < end else {
                    throw CSVError(msg: "\(klass)的第\(part(1))节时间无效")
                }
                let (subject, teacher) = course(text)
                result.lessons.append(SchoolLesson(klass: klass, weekday: weekday, period: "第\(part(1))节", start: start, end: end, subject: subject, teacher: teacher, weeks: nil))
            }
        }
        // 早晚读：按标题识别区块；合并单元格里的残留文本不作为另一次课程。
        var kind = ""
        for r in 0..<reading.count {
            let first = cell(reading, r, 0)
            if first.contains("早读安排") { kind = "早读"; continue }
            if first.contains("晚读安排") { kind = "晚读"; continue }
            let klass = className(first)
            guard result.classes.contains(klass), !kind.isEmpty else { continue }
            let evening = kind == "晚读"
            for d in 1...(evening ? 4 : 5) {
                let col = 1 + (d - 1) * 2
                let split = (!evening && d == 5) || (evening && d == 1 && !klass.hasPrefix("八"))
                let columns = split ? [col, evening ? col + 1 : 11] : [col]
                for (index, c) in columns.enumerated() {
                    let text = cell(reading, r, c)
                    guard !text.isEmpty else { throw CSVError(msg: "\(klass)周\(d)的\(kind)安排为空") }
                    let (subject, teacher) = course(text)
                    let start = evening ? "18:40" : (d == 1 ? "08:10" : "07:30")
                    let end = evening ? "19:00" : (d == 1 ? "08:30" : "07:50")
                    result.lessons.append(SchoolLesson(klass: klass, weekday: d, period: kind, start: start, end: end, subject: subject, teacher: teacher, weeks: split ? (index == 0 ? "odd" : "even") : nil))
                }
            }
        }
        guard !result.classes.isEmpty, !result.lessons.isEmpty,
              Set(result.classes).count == result.classes.count else { throw CSVError(msg: "没有识别出有效班级课表，或存在重复班级") }
        for klass in result.classes {
            guard result.lessons.contains(where: { $0.klass == klass && $0.period == "早读" }),
                  result.lessons.contains(where: { $0.klass == klass && $0.period == "晚读" }) else {
                throw CSVError(msg: "\(klass)缺少早读或晚读安排")
            }
        }
        return result
    }
}

extension AppDelegate {
    func isSchoolLessonCurrent(_ lesson: SchoolLesson, on date: Date, now: Date = Date()) -> Bool {
        guard Calendar.current.isDate(date, inSameDayAs: now),
              let start = minutes(lesson.start), let end = minutes(lesson.end) else { return false }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        return minute >= start && minute < end
    }

    func currentSchoolLesson(now: Date = Date()) -> SchoolLesson? {
        schoolItems(on: schoolDate).first { isSchoolLessonCurrent($0, on: schoolDate, now: now) }
    }

    func schoolCurrentKey(now: Date = Date()) -> String {
        let lesson = currentSchoolLesson(now: now)
        return "\(dateKey(now))#\(lesson?.period ?? "")#\(lesson?.start ?? "")"
    }

    func isMySchoolLesson(_ lesson: SchoolLesson, on date: Date) -> Bool {
        guard inSemester(date), !isSkipped(date) else { return false }
        let klass = SchoolIO.className(lesson.klass)
        return lessons(on: date).contains { personal in
            let classes = personal.klass.replacingOccurrences(of: "／", with: "/")
                .split(separator: "/").map { SchoolIO.className(String($0)).replacingOccurrences(of: "班", with: "") }
            guard classes.contains(klass.replacingOccurrences(of: "班", with: "")),
                  personal.start == lesson.start, personal.end == lesson.end else { return false }
            var subject = personal.subject
            for suffix in ["早读", "晚读", "培优"] where subject.hasSuffix(suffix) {
                subject = String(subject.dropLast(suffix.count))
            }
            return lesson.subject.split(separator: "/").contains { String($0) == subject }
        }
    }

    func schoolItems(on date: Date) -> [SchoolLesson] {
        guard let data = schoolStore.data, inSemester(date) else { return [] }
        let odd = isOddWeek(date)
        return data.lessons.filter {
            $0.klass == schoolStore.selectedClass && $0.weekday == weekdayNumber(date)
                && ($0.weeks == nil || ($0.weeks == "odd") == odd)
        }.map { lesson in
            var resolved = lesson
            // 这两处已由个人课表确认：历史单周、政治双周。
            // 保留原始总表，导入同结构课表后仍按这一已确认安排查询。
            let sharedPeriod = (lesson.klass == "七1班" && lesson.weekday == 4 && lesson.period == "第1节")
                || (lesson.klass == "八2班" && lesson.weekday == 5 && lesson.period == "第2节")
            if sharedPeriod && lesson.subject == "政治/历史" && lesson.teacher == "肖婷、陈可" {
                resolved.subject = odd ? "历史" : "政治"
                resolved.teacher = odd ? "陈可" : "肖婷"
            }
            return resolved
        }.sorted { $0.start < $1.start }
    }

    func schoolEmptyText() -> String {
        guard schoolStore.data != nil else { return "请先导入各班课表" }
        if !inSemester(schoolDate) { return "这一天不在已设置的学期内" }
        return "当天未安排课程"
    }

    func schoolShiftDay(_ offset: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: offset, to: schoolDate) {
            schoolDate = date; refreshPopover()
        }
    }

    func schoolToday() {
        schoolDate = Calendar.current.startOfDay(for: Date())
        schoolMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: schoolDate))!
        refreshPopover()
    }

    @objc func selectSchoolClass(_ sender: NSPopUpButton) {
        guard let klass = sender.titleOfSelectedItem else { return }
        schoolStore.selectedClass = klass
        UserDefaults.standard.set(klass, forKey: "schoolSelectedClass")
        refreshPopover()
    }

    func importSchool() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择含有「班级总课表」「早晚读」的学校总课表"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try SchoolIO.parse(url)
            try schoolStore.save(data)
            refreshPopover()
            alertOK("各班课表已更新", "\(data.classes.count) 个班，\(data.effectiveFrom) 起生效。")
        } catch { alertOK("导入失败", error.localizedDescription) }
    }
}

extension ScheduleView {
    func buildSchool() {
        guard let owner else { return }
        schoolTimeKey = owner.schoolCurrentKey(now: displayNow)
        let current = owner.currentSchoolLesson(now: displayNow)
        let calendar = owner.viewMode == .schoolCalendar
        var y: CGFloat = 20
        menuChip("我的课表", symbol: nil, rect: NSRect(x: 20, y: y, width: 176, height: 30)) {
            [weak owner] in owner?.viewMode = .schedule; owner?.refreshPopover()
        }
        menuChip("班级课表", symbol: nil, rect: NSRect(x: 204, y: y, width: 176, height: 30), primary: true) {}
        y += 42
        label(self, "班级", .systemFont(ofSize: 13, weight: .medium), .secondaryLabelColor,
              NSRect(x: 20, y: y + 6, width: 60, height: 20))
        let chooser = NSPopUpButton(frame: NSRect(x: 120, y: y, width: 160, height: 30))
        chooser.addItems(withTitles: owner.schoolStore.data?.classes ?? [])
        chooser.selectItem(withTitle: owner.schoolStore.selectedClass)
        chooser.target = owner
        chooser.action = #selector(AppDelegate.selectSchoolClass(_:))
        chooser.font = .systemFont(ofSize: 15, weight: .semibold)
        chooser.alignment = .center
        chooser.isBordered = false
        chooser.wantsLayer = true
        chooser.layer?.cornerRadius = 15
        chooser.layer?.backgroundColor = dyn(NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.12)).cgColor
        chooser.isEnabled = chooser.numberOfItems > 0
        addSubview(chooser)
        menuChip(calendar ? "返回" : "日历", symbol: nil, rect: NSRect(x: 310, y: y, width: 70, height: 30)) {
            [weak owner] in
            guard let owner else { return }
            owner.viewMode = calendar ? .school : .schoolCalendar
            owner.schoolMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: owner.schoolDate))!
            owner.refreshPopover()
        }
        y += 42
        if calendar {
            y = schoolCalendarGrid(y, owner)
        } else {
            menuChip("‹", symbol: nil, rect: NSRect(x: 20, y: y, width: 30, height: 28)) { [weak owner] in owner?.schoolShiftDay(-1) }
            menuChip("›", symbol: nil, rect: NSRect(x: 54, y: y, width: 30, height: 28)) { [weak owner] in owner?.schoolShiftDay(1) }
            label(self, "\(monthDay(owner.schoolDate)) \(weekdayNames[weekdayNumber(owner.schoolDate)])", .systemFont(ofSize: 16, weight: .bold), .labelColor, NSRect(x: 90, y: y + 4, width: 220, height: 22), align: .center)
            menuChip("今天", symbol: nil, rect: NSRect(x: 320, y: y, width: 60, height: 28)) { [weak owner] in owner?.schoolToday() }
            y += 38
        }
        label(self, "\(dateKey(owner.schoolDate)) · \(owner.weekLabel(owner.schoolDate))", .systemFont(ofSize: 11.5), .secondaryLabelColor, NSRect(x: 20, y: y, width: 360, height: 18))
        y += 26
        let reference = owner.schoolStore.data.flatMap { data in
            dateKey(owner.schoolDate) < data.effectiveFrom && owner.inSemester(owner.schoolDate)
                ? "按 \(data.effectiveFrom) 版课表参考" : nil
        }
        let liveStatus = Calendar.current.isDate(owner.schoolDate, inSameDayAs: displayNow)
            ? current.map { "正在上\($0.period) · \($0.end) 下课" } ?? "当前没有正在进行的课程"
            : "早读、正课、晚读"
        label(self, reference ?? liveStatus, .systemFont(ofSize: 10.5), .secondaryLabelColor,
              NSRect(x: 20, y: y - 3, width: 255, height: 18))
        y += 24
        let items = owner.schoolItems(on: owner.schoolDate)
        label(self, "蓝色为我的课", .systemFont(ofSize: 11, weight: .medium), Palette.accent,
              NSRect(x: 280, y: y - 26, width: 100, height: 18), align: .right)
        for (x, width, title) in [(CGFloat(12), CGFloat(100), "节次 / 时间"), (116, 120, "课程"), (242, 104, "教师")] {
            label(self, title, .systemFont(ofSize: 11, weight: .medium), .secondaryLabelColor,
                  NSRect(x: 20 + x, y: y, width: width, height: 18), align: .center)
        }
        y += 26
        let footerY = Self.panelHeight - 50
        let viewport = footerY - 14 - y
        let scroll = NSScrollView(frame: NSRect(x: 20, y: y, width: 360, height: viewport))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 14
        scroll.layer?.backgroundColor = dyn(NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0.07)).cgColor
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: max(viewport, CGFloat(items.count) * 60 + 12)))
        if items.isEmpty {
            label(content, owner.schoolEmptyText(), .systemFont(ofSize: 12), .secondaryLabelColor, NSRect(x: 12, y: 20, width: 325, height: 24))
        }
        for (i, lesson) in items.enumerated() {
            let top = CGFloat(i) * 60 + 10
            let mine = owner.isMySchoolLesson(lesson, on: owner.schoolDate)
            let isCurrent = owner.isSchoolLessonCurrent(lesson, on: owner.schoolDate, now: displayNow)
            if isCurrent {
                let highlight = NSView(frame: NSRect(x: 8, y: top - 3, width: 344, height: 55))
                highlight.wantsLayer = true
                highlight.layer?.cornerRadius = 8
                highlight.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.10).cgColor
                content.addSubview(highlight)
            }
            label(content, lesson.period, .systemFont(ofSize: 12, weight: .semibold), mine ? Palette.accent : .secondaryLabelColor, NSRect(x: 12, y: top + 1, width: 100, height: 18), align: .center)
            label(content, "\(lesson.start)–\(lesson.end)", .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular), mine ? Palette.accent : .secondaryLabelColor, NSRect(x: 12, y: top + 24, width: 100, height: 16), align: .center)
            label(content, lesson.subject, .systemFont(ofSize: 14, weight: .semibold), mine ? Palette.accent : .labelColor, NSRect(x: 116, y: top + (isCurrent ? 1 : 12), width: 120, height: 21), align: .center)
            if isCurrent {
                label(content, "进行中", .systemFont(ofSize: 10.5, weight: .medium), Palette.accent,
                      NSRect(x: 116, y: top + 27, width: 120, height: 16), align: .center)
            }
            label(content, lesson.teacher, .systemFont(ofSize: 11.5), mine ? Palette.accent : .secondaryLabelColor, NSRect(x: 242, y: top + 15, width: 104, height: 17), align: .center)
            if i > 0 {
                let line = NSView(frame: NSRect(x: 16, y: top - 7, width: 328, height: 1))
                line.wantsLayer = true; line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
                content.addSubview(line)
            }
        }
        scroll.documentView = content
        addSubview(scroll)
        y += viewport + 14
        menuChip("更新各班课表", symbol: "square.and.arrow.down", rect: NSRect(x: 20, y: y, width: 150, height: 30)) { [weak owner] in owner?.importSchool() }
        label(self, "共\(items.count)节 · 上下滚动查看", .systemFont(ofSize: 11), .secondaryLabelColor, NSRect(x: 180, y: y + 7, width: 200, height: 18), align: .right)
        setFrameSize(NSSize(width: Self.W, height: Self.panelHeight))
    }

    private func schoolCalendarGrid(_ top: CGFloat, _ owner: AppDelegate) -> CGFloat {
        let cal = Calendar.current
        var y = top
        let parts = cal.dateComponents([.year, .month], from: owner.schoolMonth)
        label(self, "\(parts.year!)年\(parts.month!)月", .systemFont(ofSize: 16, weight: .bold), .labelColor, NSRect(x: 96, y: y + 3, width: 200, height: 22))
        for (x, title, delta) in [(CGFloat(20), "‹", -1), (CGFloat(54), "›", 1)] {
            menuChip(title, symbol: nil, rect: NSRect(x: x, y: y, width: 30, height: 28)) { [weak owner] in
                guard let owner, let next = cal.date(byAdding: .month, value: delta, to: owner.schoolMonth), (1900...2100).contains(cal.component(.year, from: next)) else { return }
                owner.schoolMonth = next; owner.refreshPopover()
            }
        }
        menuChip("今天", symbol: nil, rect: NSRect(x: 320, y: y, width: 60, height: 28)) { [weak owner] in owner?.schoolToday() }
        y += 36
        let width: CGFloat = 360 / 7
        for (i, title) in ["一", "二", "三", "四", "五", "六", "日"].enumerated() {
            label(self, title, .systemFont(ofSize: 11), i >= 5 ? Palette.todayAccent : .secondaryLabelColor, NSRect(x: 20 + CGFloat(i) * width, y: y, width: width, height: 16), align: .center)
        }
        y += 21
        let first = cal.date(from: parts)!
        let lead = weekdayNumber(first) - 1
        let count = cal.range(of: .day, in: .month, for: first)!.count
        for day in 1...count {
            let index = lead + day - 1
            let date = cal.date(byAdding: .day, value: day - 1, to: first)!
            let selected = cal.isDate(date, inSameDayAs: owner.schoolDate)
            let cell = Chip(frame: NSRect(x: 20 + CGFloat(index % 7) * width, y: y + CGFloat(index / 7) * 38, width: width - 3, height: 35))
            cell.wantsLayer = true; cell.layer?.cornerRadius = 8
            cell.layer?.backgroundColor = selected ? Palette.accent.cgColor : NSColor.secondaryLabelColor.withAlphaComponent(index % 7 >= 5 ? 0.10 : 0.04).cgColor
            label(cell, "\(day)", .systemFont(ofSize: 14, weight: selected ? .bold : .medium), selected ? .white : .labelColor, NSRect(x: 0, y: 2, width: width - 3, height: 17), align: .center)
            let lessons = owner.schoolItems(on: date)
            label(cell, lessons.isEmpty ? Lunar.cellText(date) : "\(lessons.count)节", .systemFont(ofSize: 9), selected ? .white : .secondaryLabelColor, NSRect(x: 0, y: 20, width: width - 3, height: 12), align: .center)
            cell.onTap = { [weak owner] in owner?.schoolDate = date; owner?.refreshPopover() }
            addSubview(cell)
        }
        return y + CGFloat((lead + count + 6) / 7) * 38 + 10
    }
}
