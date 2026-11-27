import AppKit
import UniformTypeIdentifiers

final class SchoolRegularCorner: FlippedView {
    var selected = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 0, y: 8))
        ribbon.line(to: NSPoint(x: 8, y: 0))
        ribbon.line(to: NSPoint(x: 16, y: 0))
        ribbon.line(to: NSPoint(x: 0, y: 16))
        ribbon.close()
        Palette.regular.setFill()
        ribbon.fill()
        if selected {
            NSColor.white.withAlphaComponent(0.85).setStroke()
            ribbon.lineWidth = 0.7
            ribbon.stroke()
        }
    }
}

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
    var isBreak: Bool { ["大课间", "午休", "晚餐"].contains(period) }
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
    static func includesClass(_ group: String, _ klass: String) -> Bool {
        let target = className(klass).replacingOccurrences(of: "班", with: "")
        return group.replacingOccurrences(of: "／", with: "/").split(separator: "/").contains {
            className(String($0)).replacingOccurrences(of: "班", with: "") == target
        }
    }
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
    func mySchoolLessons(on date: Date) -> [Lesson] {
        guard inSemester(date), !isSkipped(date) else { return [] }
        return lessons(on: date).filter { SchoolIO.includesClass($0.klass, schoolStore.selectedClass) }
    }
    func schoolDayMarkers(on date: Date) -> (regular: Int, reading: Int) {
        var regular = 0, reading = 0
        for lesson in mySchoolLessons(on: date) {
            if lesson.period == 0 || lesson.subject.contains("早读") || lesson.subject.contains("晚读") {
                reading += 1
            } else if lesson.period > 0 && !lesson.subject.contains("晚自习") && !lesson.subject.contains("晚修") {
                // 培优按正课标识，不沿用个人日历的课型配色规则。
                regular += 1
            }
        }
        return (regular, reading)
    }
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

    func schoolBreaks(on date: Date) -> [SchoolLesson] {
        let items = schoolItems(on: date)
        guard !items.isEmpty else { return [] }
        let morningEnd = items.first { $0.start > "10:05" && $0.start < "10:30" }?.start ?? "10:30"
        return [("大课间", "10:05", morningEnd), ("午休", "12:05", "14:30"), ("晚餐", "17:45", "18:40")].map {
            SchoolLesson(klass: schoolStore.selectedClass, weekday: weekdayNumber(date), period: $0.0,
                         start: $0.1, end: $0.2, subject: $0.0, teacher: "", weeks: nil)
        }
    }

    func currentSchoolBreak(now: Date = Date()) -> SchoolLesson? {
        guard currentSchoolLesson(now: now) == nil else { return nil }
        return schoolBreaks(on: schoolDate).first { isSchoolLessonCurrent($0, on: schoolDate, now: now) }
    }

    func schoolTimeline(on date: Date) -> [SchoolLesson] {
        let items = schoolItems(on: date)
        let breaks = schoolBreaks(on: date).filter { rest in
            let following = rest.period == "大课间" ? "第4节" : (rest.period == "午休" ? "第6节" : "晚读")
            return items.contains { $0.period == following }
        }
        return (items + breaks).sorted { $0.start < $1.start }
    }

    func schoolCurrentKey(now: Date = Date()) -> String {
        let lesson = currentSchoolLesson(now: now) ?? currentSchoolBreak(now: now)
        return "\(dateKey(now))#\(lesson?.period ?? "")#\(lesson?.start ?? "")"
    }

    func isMySchoolLesson(_ lesson: SchoolLesson, on date: Date) -> Bool {
        guard inSemester(date), !isSkipped(date) else { return false }
        let klass = SchoolIO.className(lesson.klass)
        return lessons(on: date).contains { personal in
            guard SchoolIO.includesClass(personal.klass, klass),
                  personal.start == lesson.start, personal.end == lesson.end else { return false }
            if lesson.subject == "培优", personal.subject.hasSuffix("培优") { return true }
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
        var items = data.lessons.filter {
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
        }
        // 与手机版一致：有课的工作日补齐总表中留空的第9节培优。
        if (1...5).contains(weekdayNumber(date)), data.classes.contains(schoolStore.selectedClass),
           !items.isEmpty, !items.contains(where: { $0.period == "第9节" }) {
            items.append(SchoolLesson(klass: schoolStore.selectedClass, weekday: weekdayNumber(date),
                                      period: "第9节", start: "17:05", end: "17:45", subject: "培优", teacher: "", weeks: nil))
        }
        return items.sorted { $0.start < $1.start }
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
        let currentBreak = owner.currentSchoolBreak(now: displayNow)
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
            buildSchoolCalendarDetails(y, owner)
            return
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
            ? current.map { "正在上\($0.period) · \($0.end) 下课" }
                ?? currentBreak.map { "\($0.period)中 · \($0.end) 结束" } ?? "当前没有正在进行的课程"
            : "早读、正课、晚读"
        label(self, reference ?? liveStatus, .systemFont(ofSize: 10.5), .secondaryLabelColor,
              NSRect(x: 20, y: y - 3, width: 255, height: 18))
        y += 24
        let items = owner.schoolItems(on: owner.schoolDate)
        let timeline = owner.schoolTimeline(on: owner.schoolDate)
        label(self, "蓝色为我的课", .systemFont(ofSize: 11, weight: .medium), Palette.accent,
              NSRect(x: 280, y: y - 26, width: 100, height: 18), align: .right)
        for (x, width, title) in [(CGFloat(12), CGFloat(100), "节次 / 时间"), (116, 120, "课程"), (242, 104, "教师")] {
            label(self, title, .systemFont(ofSize: 11, weight: .medium), .secondaryLabelColor,
                  NSRect(x: 20 + x, y: y, width: width, height: 18), align: .center)
        }
        y += 26
        let footerY = Self.panelHeight - 50
        let viewport = footerY - 14 - y
        schoolCourseList(owner, timeline: timeline, frame: NSRect(x: 20, y: y, width: 360, height: viewport))
        y += viewport + 14
        menuChip("更新各班课表", symbol: "square.and.arrow.down", rect: NSRect(x: 20, y: y, width: 150, height: 30)) { [weak owner] in owner?.importSchool() }
        label(self, "共\(items.count)节 · 上下滚动查看", .systemFont(ofSize: 11), .secondaryLabelColor, NSRect(x: 180, y: y + 7, width: 200, height: 18), align: .right)
        setFrameSize(NSSize(width: Self.W, height: Self.panelHeight))
    }

    private func buildSchoolCalendarDetails(_ top: CGFloat, _ owner: AppDelegate) {
        let date = owner.schoolDate
        let height = Self.panelHeight
        let divider = NSView(frame: NSRect(x: 400, y: 20, width: 1, height: height - 40))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        addSubview(divider)

        label(self, "\(owner.schoolStore.selectedClass) · 完整课表", .systemFont(ofSize: 18, weight: .bold), .labelColor,
              NSRect(x: 420, y: 20, width: 360, height: 26), align: .center)
        label(self, "\(dateKey(date)) \(weekdayNames[weekdayNumber(date)]) · \(owner.weekLabel(date))",
              .systemFont(ofSize: 11.5), .secondaryLabelColor, NSRect(x: 420, y: 52, width: 360, height: 18), align: .center)
        let current = owner.currentSchoolLesson(now: displayNow)
        let rest = owner.currentSchoolBreak(now: displayNow)
        let status: String
        if Calendar.current.isDate(date, inSameDayAs: displayNow) {
            status = current.map { "正在上\($0.period) · \($0.end) 下课" }
                ?? rest.map { "\($0.period)中 · \($0.end) 结束" } ?? "当前没有正在进行的课程"
        } else if let data = owner.schoolStore.data, dateKey(date) < data.effectiveFrom, owner.inSemester(date) {
            status = "按 \(data.effectiveFrom) 版课表参考"
        } else { status = "早读、正课、培优、晚读" }
        label(self, status, .systemFont(ofSize: 11), .secondaryLabelColor,
              NSRect(x: 420, y: 80, width: 360, height: 18), align: .center)
        for (x, width, title) in [(CGFloat(12), CGFloat(100), "节次 / 时间"), (116, 120, "课程"), (242, 104, "教师")] {
            label(self, title, .systemFont(ofSize: 11, weight: .medium), .secondaryLabelColor,
                  NSRect(x: 420 + x, y: 110, width: width, height: 18), align: .center)
        }
        schoolCourseList(owner, timeline: owner.schoolTimeline(on: date),
                         frame: NSRect(x: 420, y: 138, width: 360, height: height - 202))
        label(self, "共\(owner.schoolItems(on: date).count)节 · 蓝色为我的课 · 可上下滚动", .systemFont(ofSize: 11), .secondaryLabelColor,
              NSRect(x: 420, y: height - 43, width: 360, height: 20), align: .center)

        label(self, "\(monthDay(date)) \(weekdayNames[weekdayNumber(date)])", .systemFont(ofSize: 14, weight: .bold), .labelColor,
              NSRect(x: 20, y: top + 4, width: 360, height: 21))
        let mine = owner.mySchoolLessons(on: date)
        label(self, "我在\(owner.schoolStore.selectedClass)的课 · \(mine.count)节", .systemFont(ofSize: 12, weight: .semibold), Palette.accent,
              NSRect(x: 20, y: top + 31, width: 360, height: 19))
        let scrollY = top + 58
        let viewport = height - 64 - scrollY
        let scroll = NSScrollView(frame: NSRect(x: 20, y: scrollY, width: 360, height: viewport))
        scroll.identifier = NSUserInterfaceItemIdentifier("school-personal-summary")
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: max(viewport, CGFloat(mine.count) * 58)))
        if mine.isEmpty {
            label(content, "当天没有我的课", .systemFont(ofSize: 12), .secondaryLabelColor,
                  NSRect(x: 0, y: 18, width: 360, height: 20), align: .center)
        }
        for (i, lesson) in mine.enumerated() {
            let y = CGFloat(i) * 58
            let band = FlippedView(frame: NSRect(x: 0, y: y, width: 360, height: 52))
            band.wantsLayer = true
            band.layer?.cornerRadius = 10
            band.layer?.backgroundColor = dyn(NSColor.white.withAlphaComponent(0.45), NSColor.white.withAlphaComponent(0.06)).cgColor
            label(band, lesson.subject, .systemFont(ofSize: 13, weight: .semibold), Palette.accent,
                  NSRect(x: 14, y: 5, width: 332, height: 19))
            let period = lesson.period > 0 ? " · 第\(lesson.period)节" : ""
            label(band, "\(lesson.start)–\(lesson.end)\(period)", .monospacedDigitSystemFont(ofSize: 11, weight: .regular), Palette.accent,
                  NSRect(x: 14, y: 29, width: 332, height: 17))
            content.addSubview(band)
        }
        scroll.documentView = content
        addSubview(scroll)
        menuChip("更新各班课表", symbol: "square.and.arrow.down", rect: NSRect(x: 20, y: height - 50, width: 150, height: 30)) {
            [weak owner] in owner?.importSchool()
        }
        setFrameSize(NSSize(width: Self.W * 2, height: height))
    }

    private func schoolCourseList(_ owner: AppDelegate, timeline: [SchoolLesson], frame: NSRect) {
        let viewport = frame.height
        let items = timeline.filter { !$0.isBreak }
        let currentBreak = owner.currentSchoolBreak(now: displayNow)
        let scroll = NSScrollView(frame: frame)
        scroll.identifier = NSUserInterfaceItemIdentifier("school-course-list")
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 14
        scroll.layer?.backgroundColor = dyn(NSColor.white.withAlphaComponent(0.6), NSColor.white.withAlphaComponent(0.07)).cgColor
        let listHeight = timeline.reduce(CGFloat(12)) { $0 + ($1.isBreak ? 48 : 60) }
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: max(viewport, listHeight)))
        if items.isEmpty {
            label(content, owner.schoolEmptyText(), .systemFont(ofSize: 12), .secondaryLabelColor, NSRect(x: 12, y: 20, width: 325, height: 24))
        }
        var top: CGFloat = 10
        for (i, lesson) in timeline.enumerated() {
            if lesson.isBreak {
                let active = currentBreak?.period == lesson.period
                let band = FlippedView(frame: NSRect(x: 8, y: top - 2, width: 344, height: 40))
                band.wantsLayer = true
                band.layer?.cornerRadius = 9
                band.layer?.backgroundColor = Palette.todayAccent.withAlphaComponent(active ? 0.19 : 0.07).cgColor
                label(band, active ? "\(lesson.period)中" : lesson.period, .systemFont(ofSize: 12, weight: .semibold),
                      active ? Palette.todayAccent : .secondaryLabelColor, NSRect(x: 0, y: 3, width: 344, height: 17), align: .center)
                label(band, "\(lesson.start)–\(lesson.end)", .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                      .secondaryLabelColor, NSRect(x: 0, y: 22, width: 344, height: 15), align: .center)
                content.addSubview(band)
                top += 48
                continue
            }
            let mine = owner.isMySchoolLesson(lesson, on: owner.schoolDate)
            let isCurrent = owner.isSchoolLessonCurrent(lesson, on: owner.schoolDate, now: displayNow)
            let readingColor: NSColor? = lesson.period == "早读"
                ? dyn(NSColor(srgbRed: 0.07, green: 0.43, blue: 0.38, alpha: 1),
                      NSColor(srgbRed: 0.40, green: 0.82, blue: 0.69, alpha: 1))
                : lesson.period == "晚读"
                    ? dyn(NSColor(srgbRed: 0.44, green: 0.28, blue: 0.67, alpha: 1),
                          NSColor(srgbRed: 0.75, green: 0.61, blue: 0.94, alpha: 1)) : nil
            let primaryInk = mine ? Palette.accent : (readingColor ?? .labelColor)
            let secondaryInk = mine ? Palette.accent : (readingColor ?? .secondaryLabelColor)
            if isCurrent || readingColor != nil {
                let highlight = NSView(frame: NSRect(x: 8, y: top - 3, width: 344, height: 55))
                highlight.wantsLayer = true
                highlight.layer?.cornerRadius = 8
                highlight.layer?.backgroundColor = (isCurrent ? Palette.accent : readingColor!)
                    .withAlphaComponent(isCurrent ? 0.10 : 0.07).cgColor
                content.addSubview(highlight)
            }
            label(content, lesson.period, .systemFont(ofSize: 12, weight: .semibold), secondaryInk, NSRect(x: 12, y: top + 1, width: 100, height: 18), align: .center)
            label(content, "\(lesson.start)–\(lesson.end)", .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular), secondaryInk, NSRect(x: 12, y: top + 24, width: 100, height: 16), align: .center)
            label(content, lesson.subject, .systemFont(ofSize: 14, weight: .semibold), primaryInk, NSRect(x: 116, y: top + (isCurrent ? 1 : 12), width: 120, height: 21), align: .center)
            if isCurrent {
                label(content, "进行中", .systemFont(ofSize: 10.5, weight: .medium), Palette.accent,
                      NSRect(x: 116, y: top + 27, width: 120, height: 16), align: .center)
            }
            label(content, lesson.teacher, .systemFont(ofSize: 11.5), secondaryInk, NSRect(x: 242, y: top + 15, width: 104, height: 17), align: .center)
            if i > 0 {
                let line = NSView(frame: NSRect(x: 16, y: top - 7, width: 328, height: 1))
                line.wantsLayer = true; line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
                content.addSubview(line)
            }
            top += 60
        }
        scroll.documentView = content
        addSubview(scroll)
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
        let cellCount = ((lead + count + 6) / 7) * 7
        for index in 0..<cellCount {
            let date = cal.date(byAdding: .day, value: index - lead, to: first)!
            let day = cal.component(.day, from: date)
            let inMonth = cal.isDate(date, equalTo: first, toGranularity: .month)
            let selected = cal.isDate(date, inSameDayAs: owner.schoolDate)
            let cell = Chip(frame: NSRect(x: 20 + CGFloat(index % 7) * width, y: y + CGFloat(index / 7) * 38, width: width - 3, height: 35))
            cell.identifier = NSUserInterfaceItemIdentifier("school-calendar-day-\(dateKey(date))")
            cell.wantsLayer = true; cell.layer?.cornerRadius = 8
            cell.layer?.masksToBounds = true
            cell.layer?.backgroundColor = !inMonth ? NSColor.clear.cgColor
                : selected ? Palette.accent.cgColor : NSColor.secondaryLabelColor.withAlphaComponent(index % 7 >= 5 ? 0.14 : 0.085).cgColor
            let outsideColor = dyn(NSColor(white: 0.62, alpha: 1), NSColor(white: 0.46, alpha: 1))
            let numberColor: NSColor = !inMonth ? outsideColor : (selected ? .white : .labelColor)
            let dayText = inMonth ? "\(day)" : "\(cal.component(.month, from: date))/\(day)"
            label(cell, dayText, .systemFont(ofSize: inMonth ? 14 : 10.5, weight: !inMonth ? .regular : (selected ? .bold : .medium)), numberColor, NSRect(x: 0, y: 2, width: width - 3, height: 17), align: .center)
            let lessons = owner.schoolItems(on: date)
            label(cell, !inMonth || lessons.isEmpty ? Lunar.cellText(date) : "\(lessons.count)节", .systemFont(ofSize: 9), !inMonth ? outsideColor : (selected ? .white : .secondaryLabelColor), NSRect(x: 0, y: 20, width: width - 3, height: 12), align: .center)
            let mine = owner.mySchoolLessons(on: date)
            let markers = owner.schoolDayMarkers(on: date)
            cell.toolTip = "\(dateKey(date)) · 班级\(lessons.count)节 · 我有\(mine.count)节课（正课/培优\(markers.regular)节，早晚读\(markers.reading)节）"
            if inMonth && markers.regular > 0 {
                let corner = SchoolRegularCorner(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
                corner.identifier = NSUserInterfaceItemIdentifier("school-personal-regular-\(dateKey(date))")
                corner.selected = selected
                cell.addSubview(corner)
            }
            if inMonth && markers.reading > 0 {
                let dot = NSView(frame: NSRect(x: cell.frame.width - 10, y: 4, width: 6, height: 6))
                dot.identifier = NSUserInterfaceItemIdentifier("school-personal-reading-\(dateKey(date))")
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.layer?.backgroundColor = Palette.accent.cgColor
                if selected {
                    dot.layer?.borderWidth = 1.2
                    dot.layer?.borderColor = NSColor.white.cgColor
                }
                cell.addSubview(dot)
            }
            cell.onTap = { [weak owner] in
                guard let owner, (1900...2100).contains(cal.component(.year, from: date)) else { return }
                owner.schoolDate = date
                if !inMonth { owner.schoolMonth = cal.date(from: cal.dateComponents([.year, .month], from: date))! }
                owner.refreshPopover()
            }
            addSubview(cell)
        }
        let bottom = y + CGFloat((lead + count + 6) / 7) * 38
        let corner = SchoolRegularCorner(frame: NSRect(x: 22, y: bottom + 4, width: 16, height: 16))
        addSubview(corner)
        label(self, "我的正课 / 培优", .systemFont(ofSize: 10.5), .secondaryLabelColor,
              NSRect(x: 44, y: bottom + 3, width: 140, height: 18))
        let dot = NSView(frame: NSRect(x: 208, y: bottom + 8, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = Palette.accent.cgColor
        addSubview(dot)
        label(self, "我的早读 / 晚读", .systemFont(ofSize: 10.5), .secondaryLabelColor,
              NSRect(x: 220, y: bottom + 3, width: 160, height: 18))
        return bottom + 30
    }
}
