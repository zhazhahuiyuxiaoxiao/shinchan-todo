import Foundation
import TodoCore
import TodoSystem

@MainActor func focusUsesElapsedTimeAndFinishesOnce() {
    let task = TodoTask(id: "study", calendarID: "bound", title: "学习")
    var engine = FocusEngine()
    engine.start(key: FocusKey(task: task), minutes: 1, kind: .work, monotonic: 100, date: Date())
    engine.tick(monotonic: 137, date: Date())
    expect(engine.archive.run?.remaining == 23)
    engine.pause(monotonic: 142, date: Date())
    expect(engine.archive.run?.remaining == 18)
    engine.tick(monotonic: 500, date: Date())
    expect(engine.archive.run?.remaining == 18)
    engine.resume(monotonic: 500)
    engine.tick(monotonic: 520, date: Date(timeIntervalSince1970: 1000))
    engine.tick(monotonic: 900, date: Date())
    expect(engine.archive.records.count == 1)
    expect(engine.archive.run?.remaining == 0)
    expect(engine.archive.records.first?.minutes == 1)
    engine.reset()
    expect(engine.archive.run?.remaining == 60)
    expect(engine.archive.run?.running == false)
    expect(engine.archive.records.count == 1)
}

@MainActor func focusRestAbandonAndRecovery() {
    let key = FocusKey(task: TodoTask(id: "a", calendarID: "bound", title: "任务"))
    var engine = FocusEngine()
    engine.start(key: key, minutes: 1, kind: .rest, monotonic: 0, date: Date())
    engine.tick(monotonic: 70, date: Date())
    expect(engine.archive.records.isEmpty)
    engine.start(key: key, minutes: 25, kind: .work, monotonic: 100, date: Date())
    engine.pause(monotonic: 110, date: Date())
    expect(engine.archive.run?.remaining == 1490)
    engine.resume(monotonic: 200)
    engine.tick(monotonic: 205, date: Date())
    let restored = FocusEngine(archive: engine.archive)
    expect(restored.archive.run?.running == false)
    expect(restored.archive.run?.remaining == 1485)
    engine.abandon()
    expect(engine.archive.run == nil); expect(engine.archive.records.isEmpty)
}

@MainActor func focusDailyInstancesAndStatistics() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    var task = TodoTask(id: "daily", calendarID: "bound", title: "每天学习", dueDate: yesterday, repeatRule: .daily)
    let old = FocusKey(task: task); task.dueDate = today
    let next = FocusKey(task: task); expect(old != next)
    var engine = FocusEngine()
    engine.start(key: old, minutes: 1, kind: .work, monotonic: 0, date: yesterday)
    engine.tick(monotonic: 60, date: yesterday)
    engine.start(key: next, minutes: 2, kind: .work, monotonic: 100, date: today)
    engine.tick(monotonic: 220, date: today)
    let stats = FocusStatistics(records: engine.archive.records, now: today, calendar: calendar)
    expect(stats.todayCount == 1); expect(stats.weekCount == 1)
    expect(stats.todayMinutes == 2); expect(stats.weekMinutes == 2)
    expect(FocusStatistics(records: [], now: today, calendar: calendar).todayCount == 0)
}

@MainActor func focusSummaryPreservesNotesAndRejectsMalformedBlocks() throws {
    let text = "第一行\n中文长备注  🍅\n\n"
    let summary = FocusSummary(minutes: 40, rounds: 2, totalMinutes: 80, lastCompleted: Date(timeIntervalSince1970: 1000), occurrence: "单次")
    let combined = try FocusNotes.replacing(in: text, summary: summary)
    let parsed = try FocusNotes.parse(combined)
    expect(parsed.userNotes == text)
    expect(parsed.summary == summary)
    let edited = try FocusNotes.composing(userNotes: "手机修改后的文字", preserving: combined)
    let parsedEdit = try FocusNotes.parse(edited)
    expect(parsedEdit.userNotes == "手机修改后的文字")
    expect(parsedEdit.summary == summary)
    for invalid in [combined + combined, "正文\n【小新专注 v1】\n坏数据", combined.replacingOccurrences(of: "每轮分钟：40", with: "每轮分钟：999")] {
        do { _ = try FocusNotes.replacing(in: invalid, summary: summary); expect(false) } catch { }
    }
}

@MainActor func focusFileRoundTripAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileFocusStore(url: directory.appendingPathComponent("focus.json"))
    var archive = FocusArchive(); archive.restMinutes = 10
    try store.save(archive)
    let loaded = try store.load(); expect(loaded.restMinutes == 10)
    let corrupt = Data("not json".utf8); try corrupt.write(to: store.url)
    do { _ = try store.load(); expect(false) } catch { }
    let retained = try Data(contentsOf: store.url); expect(retained == corrupt)
    let invalid = FileFocusStore(url: directory.appendingPathComponent("focus.json/child"))
    do { try invalid.save(archive); expect(false) } catch { }
}

@MainActor func focusDurationTextRejectsInvalidInput() {
    expect(FocusDurationInput.minutes(from: "45", in: 1...180) == 45)
    expect(FocusDurationInput.minutes(from: " 60 ", in: 1...60) == 60)
    expect(FocusDurationInput.minutes(from: "1", in: 1...180) == 1)
    expect(FocusDurationInput.minutes(from: "180", in: 1...180) == 180)
    for text in ["", " ", "0", "181", "-1", "+25", "1.5", "abc", "25分钟", "999999999999999999999999"] {
        expect(FocusDurationInput.minutes(from: text, in: 1...180) == nil)
    }
    expect(FocusDurationInput.minutes(from: "61", in: 1...60) == nil)
}

@MainActor func focusDurationSettingsDoNotChangeActiveRun() async {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let store = MemoryFocusStore()
    let focus = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier())
    if let minutes = FocusDurationInput.minutes(from: "45", in: 1...180) { focus.setMinutes(minutes, for: todo.tasks[0]) }
    expect(focus.minutes(for: todo.tasks[0]) == 45)
    await focus.start(todo.tasks[0])
    expect(focus.archive.run?.minutes == 45)
    focus.setMinutes(90, for: todo.tasks[0])
    expect(focus.minutes(for: todo.tasks[0]) == 45)
    focus.pause(); focus.setMinutes(60, for: todo.tasks[0])
    expect(focus.archive.run?.minutes == 45)
    expect(focus.minutes(for: todo.tasks[0]) == 45)
    focus.abandon()
    focus.setMinutes(60, for: todo.tasks[0])
    focus.setRestMinutes(15)
    let restored = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier())
    expect(restored.minutes(for: todo.tasks[0]) == 60)
    expect(restored.archive.restMinutes == 15)
}
