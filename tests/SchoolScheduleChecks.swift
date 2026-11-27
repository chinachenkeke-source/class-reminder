import AppKit

func runSchoolChecks() throws {
    let original = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "school-timetable.json")
    let bundled = try JSONDecoder().decode(SchoolTimetable.self, from: Data(contentsOf: URL(fileURLWithPath: "school-timetable.json")))
    let data = original.pathExtension == "xlsx" ? try SchoolIO.parse(original) : bundled
    let encoded = try SchoolStore.encode(data)
    let bundledBytes = try SchoolStore.encode(bundled)
    assert(encoded == bundledBytes, "导入结果应与随应用提供的数据一致")
    assert(data.effectiveFrom == "2026-11-25")
    assert(data.classes == ["七1班", "八1班", "八2班", "九1班", "九2班", "九3班"])
    assert(data.lessons.count == 325)
    assert(data.lessons.filter { $0.period == "早读" }.count == 36)
    assert(data.lessons.filter { $0.period == "晚读" }.count == 28)
    assert(data.lessons.filter { $0.subject.contains("/") }.allSatisfy { $0.weeks == nil })
    assert(data.lessons.contains { $0.subject == "政治/历史" && $0.teacher == "肖婷、陈可" })
    assert(data.lessons.contains { $0.klass == "八1班" && $0.subject == "历史" && $0.teacher == "郭静" && $0.weekday == 3 })
    assert(!data.lessons.contains { $0.weekday == 1 && $0.period == "第1节" })
    assert(data.lessons.filter { $0.weekday == 1 && $0.period == "早读" }.allSatisfy { $0.start == "08:10" && $0.end == "08:30" })
    assert(data.lessons.filter { $0.weekday == 5 && $0.period == "第4节" }.allSatisfy { $0.start == "10:15" && $0.end == "10:55" })
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let owner = AppDelegate()
    owner.table = Timetable(weekAnchor: "2026-08-31", anchorIsOdd: true, semesterWeeks: 22, lessons: [])
    owner.schoolStore.data = data
    for klass in data.classes {
        owner.schoolStore.selectedClass = klass
        for dateText in ["2026-11-25", "2026-11-26", "2026-11-27", "2026-11-30", "2026-12-04"] {
            let date = parseDate(dateText)!
            let items = owner.schoolItems(on: date)
            assert(!items.isEmpty)
            assert(items.first?.period == "早读")
            assert(items.filter { $0.period == "早读" }.count == 1)
            assert(items.filter { $0.period == "晚读" }.count == (weekdayNumber(date) == 5 ? 0 : 1))
            assert(items.map(\.start) == items.map(\.start).sorted())
            assert(items.allSatisfy { $0.klass == klass })
            assert(items.filter { $0.period == "第9节" && $0.subject == "培优" && $0.start == "17:05" && $0.end == "17:45" }.count == 1)
            let timeline = owner.schoolTimeline(on: date)
            assert(timeline.map(\.start) == timeline.map(\.start).sorted())
            assert(timeline.filter(\.isBreak).map(\.period) == (weekdayNumber(date) == 5 ? ["大课间", "午休"] : ["大课间", "午休", "晚餐"]))
            assert(owner.schoolBreaks(on: date).first?.end == (weekdayNumber(date) == 5 ? "10:15" : "10:30"))
            if weekdayNumber(date) == 5 {
                let expected: String
                if klass.hasPrefix("九") { expected = owner.isOddWeek(date) ? "政治" : "历史" }
                else { expected = owner.isOddWeek(date) ? "历史" : "道法" }
                assert(items.first?.subject == expected)
            }
        }
    }
    assert(!owner.schoolItems(on: parseDate("2026-11-24")!).isEmpty)
    owner.schoolStore.selectedClass = "七1班"
    let earlierFriday = owner.schoolItems(on: parseDate("2026-11-20")!)
    assert(earlierFriday.count == 10, "11月20日也应显示早读、正课与第9节培优")
    assert(earlierFriday.first?.period == "早读")
    assert(owner.schoolItems(on: parseDate("2026-11-28")!).isEmpty)
    assert(owner.schoolItems(on: parseDate("2027-02-01")!).isEmpty)
    assert(owner.schoolTimeline(on: parseDate("2026-11-28")!).isEmpty)
    assert(owner.schoolBreaks(on: parseDate("2027-02-01")!).isEmpty)
    assert(owner.table.lessons.isEmpty, "查询不得修改个人课表")
    for (klass, dates, period) in [
        ("七1班", ["2026-11-26", "2026-12-03"], "第1节"),
        ("八2班", ["2026-11-27", "2026-12-04"], "第2节")
    ] {
        owner.schoolStore.selectedClass = klass
        for text in dates {
            let date = parseDate(text)!
            let items = owner.schoolItems(on: date).filter { $0.period == period }
            assert(items.count == 1, "共用节次每天只显示一节")
            let odd = owner.isOddWeek(date)
            assert(items[0].subject == (odd ? "历史" : "政治"))
            assert(items[0].teacher == (odd ? "陈可" : "肖婷"))
        }
    }
    owner.schoolStore.selectedClass = "八1班"
    assert(owner.schoolItems(on: parseDate("2026-11-27")!).contains { $0.subject == "政治/历史" && $0.teacher == "肖婷、郭静" })
    owner.schoolStore.selectedClass = "八2班"
    assert(owner.schoolItems(on: parseDate("2026-12-01")!).contains { $0.subject == "数学/英语" })
    owner.schoolStore.selectedClass = "七1班"
    owner.table.lessons = [
        Lesson(weekday: 4, period: 1, start: "07:50", end: "08:30", klass: "七1班", subject: "历史", weeks: "odd"),
        Lesson(weekday: 5, period: 0, start: "07:30", end: "07:50", klass: "七1/八2", subject: "历史早读", weeks: "odd"),
        Lesson(weekday: 1, period: 0, start: "18:40", end: "19:00", klass: "七1班", subject: "历史晚读", weeks: "odd")
    ]
    for text in ["2026-11-26", "2026-12-03"] {
        let date = parseDate(text)!
        let items = owner.schoolItems(on: date)
        let highlighted = items.filter { owner.isMySchoolLesson($0, on: date) }
        assert(highlighted.count == (owner.isOddWeek(date) ? 1 : 0), "只标记本人当周的课，不能把肖婷的课标蓝")
    }
    for klass in ["七1班", "八2班", "八1班"] {
        owner.schoolStore.selectedClass = klass
        for text in ["2026-11-27", "2026-12-04"] {
            let date = parseDate(text)!
            let early = owner.schoolItems(on: date).first!
            assert(owner.isMySchoolLesson(early, on: date) == (klass != "八1班" && owner.isOddWeek(date)), "合班早读应匹配到两个班，其他班不标记")
            assert(owner.mySchoolLessons(on: date).count == (klass != "八1班" && owner.isOddWeek(date) ? 1 : 0), "日历下方只列该班当天的个人课程")
        }
    }
    owner.schoolStore.selectedClass = "七1班"
    let monday = parseDate("2026-11-30")!
    let reading = owner.schoolItems(on: monday).first { $0.period == "晚读" }!
    assert(owner.isMySchoolLesson(reading, on: monday) == owner.isOddWeek(monday))
    owner.table.skipDates = ["2026-11-26"]
    assert(owner.mySchoolLessons(on: parseDate("2026-11-26")!).isEmpty)
    assert(!owner.schoolItems(on: parseDate("2026-11-26")!).contains { owner.isMySchoolLesson($0, on: parseDate("2026-11-26")!) })
    owner.table.skipDates = []
    let markerLessons = owner.table.lessons
    owner.table.lessons = [
        Lesson(weekday: 4, period: 9, start: "17:05", end: "17:45", klass: "七1班", subject: "历史培优", weeks: nil),
        Lesson(weekday: 4, period: 0, start: "07:30", end: "07:50", klass: "七1班", subject: "历史早读", weeks: nil),
        Lesson(weekday: 4, period: 11, start: "19:45", end: "21:50", klass: "七1班", subject: "晚自习", weeks: nil)
    ]
    let typedMarkers = owner.schoolDayMarkers(on: parseDate("2026-11-26")!)
    assert(typedMarkers.regular == 1 && typedMarkers.reading == 1, "培优用斜角标、早晚读用蓝点，晚自习不混入")
    owner.table.skipDates = ["2026-11-26"]
    let skippedMarkers = owner.schoolDayMarkers(on: parseDate("2026-11-26")!)
    assert(skippedMarkers.regular == 0 && skippedMarkers.reading == 0)
    owner.table.skipDates = []
    owner.table.lessons = markerLessons
    // 用真实示例课量检查个人页面与班级页面的固定外框。
    owner.table = try JSONDecoder().decode(Timetable.self, from: Data(contentsOf: URL(fileURLWithPath: "timetable.json")))
    owner.schoolStore.selectedClass = "九3班"
    let tutoringDate = parseDate("2026-12-01")!
    let tutoring = owner.schoolItems(on: tutoringDate).first { $0.period == "第9节" }!
    assert(owner.isMySchoolLesson(tutoring, on: tutoringDate) == !owner.isOddWeek(tutoringDate), "补充的培优仍需按个人课表与单双周标蓝")
    owner.schoolStore.selectedClass = "七1班"
    let sunday = parseDate("2026-12-06")!
    owner.table.lessons.append(Lesson(weekday: 7, period: 10, start: "19:00", end: "19:40", klass: "七1班", subject: "历史培优", weeks: nil))
    assert(owner.schoolItems(on: sunday).isEmpty)
    assert(!owner.mySchoolLessons(on: sunday).isEmpty, "个人周日培优不能因班级总表留空而丢失")
    owner.table.lessons.removeLast()
    owner.schoolDate = parseDate("2026-11-26")!
    owner.schoolMonth = parseDate("2026-11-01")!
    func clock(_ date: String, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: parseDate(date)!)!
    }
    let firstLesson = owner.schoolItems(on: owner.schoolDate).first { $0.period == "第1节" }!
    assert(!owner.isSchoolLessonCurrent(firstLesson, on: owner.schoolDate, now: clock("2026-11-26", 7, 49)))
    assert(owner.isSchoolLessonCurrent(firstLesson, on: owner.schoolDate, now: clock("2026-11-26", 7, 50)))
    assert(owner.isSchoolLessonCurrent(firstLesson, on: owner.schoolDate, now: clock("2026-11-26", 8, 29)))
    assert(!owner.isSchoolLessonCurrent(firstLesson, on: owner.schoolDate, now: clock("2026-11-26", 8, 30)))
    assert(!owner.isSchoolLessonCurrent(firstLesson, on: owner.schoolDate, now: clock("2026-11-25", 8, 0)), "非今日不显示当前课程底色")
    assert(owner.currentSchoolLesson(now: clock("2026-11-26", 8, 30)) == nil)
    assert(owner.currentSchoolLesson(now: clock("2026-11-26", 8, 35))?.period == "第2节")
    assert(owner.schoolCurrentKey(now: clock("2026-11-26", 8, 29)) != owner.schoolCurrentKey(now: clock("2026-11-26", 8, 30)))
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 10, 4)) == nil)
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 10, 5))?.period == "大课间")
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 10, 30)) == nil)
    assert(owner.currentSchoolLesson(now: clock("2026-11-26", 10, 30))?.period == "第4节")
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 12, 5))?.period == "午休")
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 14, 30)) == nil)
    assert(owner.currentSchoolLesson(now: clock("2026-11-26", 17, 5))?.period == "第9节")
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 17, 45))?.period == "晚餐")
    assert(owner.currentSchoolBreak(now: clock("2026-11-26", 18, 40)) == nil)
    assert(owner.schoolCurrentKey(now: clock("2026-11-26", 12, 0)) != owner.schoolCurrentKey(now: clock("2026-11-26", 12, 5)))
    owner.schoolDate = parseDate("2026-11-27")!
    assert(owner.currentSchoolBreak(now: clock("2026-11-27", 10, 14))?.end == "10:15")
    assert(owner.currentSchoolLesson(now: clock("2026-11-27", 10, 15))?.period == "第4节")
    owner.schoolDate = parseDate("2026-11-26")!
    if CommandLine.arguments.count > 2 {
        let directory = CommandLine.arguments[2]
        for (mode, name) in [(AppDelegate.ViewMode.school, "school"), (.schoolCalendar, "school-calendar"), (.schedule, "personal")] {
            owner.viewMode = mode
            let view = ScheduleView(owner: owner)
            assert(view.frame.size == NSSize(width: mode == .schoolCalendar ? 800 : 400, height: ScheduleView.panelHeight))
            assert(view.subviews.allSatisfy { $0.frame.maxY <= view.frame.height + 1 })
            if mode == .schoolCalendar {
                let scrolls = view.subviews.compactMap { $0 as? NSScrollView }
                let full = scrolls.first { $0.identifier?.rawValue == "school-course-list" }!
                let personal = scrolls.first { $0.identifier?.rawValue == "school-personal-summary" }!
                assert(full.frame.minX > 400 && full.frame.height >= 400)
                assert(personal.frame.maxX < 400)
                let markers = Set(view.subviews.flatMap(\.subviews).compactMap { $0.identifier?.rawValue })
                let days = view.subviews.compactMap { $0 as? Chip }.filter { $0.identifier?.rawValue.hasPrefix("school-calendar-day-") == true }
                assert(days.count == 42)
                let leading = days.first { $0.identifier?.rawValue == "school-calendar-day-2026-10-26" }!
                assert(days.last?.identifier?.rawValue == "school-calendar-day-2026-12-06")
                leading.onTap?()
                assert(dateKey(owner.schoolDate) == "2026-10-26" && dateKey(owner.schoolMonth) == "2026-10-01")
                owner.schoolDate = parseDate("2026-11-26")!
                owner.schoolMonth = parseDate("2026-11-01")!
                assert(markers.contains("school-personal-regular-2026-11-26") == owner.isOddWeek(parseDate("2026-11-26")!))
                assert(!markers.contains("school-personal-reading-2026-11-26"), "仅有正课时不应标早晚读蓝点")
                assert(markers.contains("school-personal-reading-2026-11-27") == owner.isOddWeek(parseDate("2026-11-27")!))
                assert(!markers.contains("school-personal-regular-2026-11-25") && !markers.contains("school-personal-reading-2026-11-25"))
            }
            owner.dumpView(view, to: "\(directory)/\(name).png")
        }
        owner.schoolMonth = parseDate("2027-01-01")!
        owner.viewMode = .schoolCalendar
        let view = ScheduleView(owner: owner)
        assert(view.frame.size == NSSize(width: 800, height: ScheduleView.panelHeight))
        assert(view.subviews.compactMap { $0.identifier?.rawValue }.filter { $0.hasPrefix("school-calendar-day-") }.count == 35)
        owner.dumpView(view, to: "\(directory)/school-calendar-five-weeks.png")
        owner.schoolDate = parseDate("2026-11-20")!
        owner.viewMode = .school
        owner.dumpView(ScheduleView(owner: owner), to: "\(directory)/school-earlier-date.png")
        owner.schoolStore.selectedClass = "九3班"
        owner.schoolDate = parseDate("2026-11-25")!
        owner.dumpView(ScheduleView(owner: owner, now: clock("2026-11-25", 9, 30)), to: "\(directory)/school-current.png")
        owner.schoolDate = parseDate("2026-11-26")!
        owner.dumpView(ScheduleView(owner: owner, now: clock("2026-11-26", 10, 15)), to: "\(directory)/school-break.png")
        owner.viewMode = .schoolCalendar
        owner.schoolMonth = parseDate("2026-11-01")!
        owner.dumpView(ScheduleView(owner: owner, now: clock("2026-11-26", 12, 30)), to: "\(directory)/school-break-calendar.png")
        owner.schoolStore.selectedClass = "八1班"
        let noPersonal = ScheduleView(owner: owner)
        assert(!noPersonal.subviews.flatMap(\.subviews).contains { $0.identifier?.rawValue.hasPrefix("school-personal-regular-") == true || $0.identifier?.rawValue.hasPrefix("school-personal-reading-") == true })
        owner.dumpView(noPersonal, to: "\(directory)/school-calendar-no-personal.png")
        owner.schoolStore.selectedClass = "八2班"
        owner.schoolDate = owner.isOddWeek(parseDate("2026-11-27")!) ? parseDate("2026-11-27")! : parseDate("2026-12-04")!
        owner.schoolMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: owner.schoolDate))!
        owner.dumpView(ScheduleView(owner: owner), to: "\(directory)/school-calendar-two-markers.png")
        owner.schoolStore.selectedClass = "九3班"
        owner.viewMode = .school
        let eveningView = ScheduleView(owner: owner, now: clock("2026-11-26", 17, 0))
        if let scroll = eveningView.subviews.compactMap({ $0 as? NSScrollView }).first {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentSize.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        owner.dumpView(eveningView, to: "\(directory)/school-reading-evening.png")
    }
    owner.viewMode = .schedule
    let base = owner.table.lessons
    for lessons in [[], base, Array(repeating: base, count: 5).flatMap { $0 }] {
        owner.table.lessons = lessons
        let view = ScheduleView(owner: owner)
        assert(view.frame.height == ScheduleView.panelHeight, "个人课量变化不应改变面板高度")
        assert(view.subviews.compactMap { $0 as? NSScrollView }.count == 1)
        assert(view.subviews.allSatisfy { $0.frame.maxY <= view.frame.height + 1 })
    }
    print("通过：6个班、325条安排、两处共用正课单双周、其他组合科目保留、早晚读单双周、时间与学期边界、个人课表隔离")
}
