import Foundation
import TodoCore
import TodoSystem

@MainActor func learningRoutesKeepManualCheckinsAndOrder() async throws {
    let backend = MemoryBoundary()
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), date: { Date(timeIntervalSince1970: 1000) })
    let route = try focus.addRoute(title: " Go 后端 ")
    let first = try focus.addStage(title: "基础", to: route)
    let second = try focus.addStage(title: "接口", to: route)
    try focus.renameRoute(route, title: "Go 学习")
    try focus.renameStage(first, in: route, title: "类型与接口")
    try focus.moveStage(second, in: route, offset: -1)
    expect(focus.archive.routes.first?.title == "Go 学习")
    expect(focus.archive.routes.first?.stages.map(\.id) == [second, first])
    try focus.toggleStage(first, in: route)
    expect(focus.archive.routes.first?.completedCount == 1)
    expect(focus.archive.routes.first?.stages.last?.completedAt == Date(timeIntervalSince1970: 1000))
    expect(focus.archive.routes.first?.nextStage(after: first)?.id == second)
    try focus.toggleStage(first, in: route)
    expect(focus.archive.routes.first?.completedCount == 0)
    do { _ = try focus.addStage(title: "  ", to: route); expect(false) } catch { }
}

@MainActor func dailyGoalCountsOnlyCompleteRoundsAndKeepsStageHistory() async throws {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "learn", calendarID: "bound", title: "学习", notes: "原备注", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    var clock = 0.0
    let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), monotonic: { clock }, date: { Date(timeIntervalSince1970: 10000 + clock) })
    let route = try focus.addRoute(title: "Go")
    let first = try focus.addStage(title: "基础", to: route)
    let second = try focus.addStage(title: "实践", to: route)
    try focus.setLearning(dailyGoal: 120, context: LearningContext(routeID: route, stageID: first), for: todo.tasks[0])
    focus.setMinutes(40, for: todo.tasks[0]); await focus.start(todo.tasks[0])
    clock = 1200; focus.tick()
    expect(focus.dailyProgress(for: todo.tasks[0]).completedMinutes == 0)
    expect(focus.dailyProgress(for: todo.tasks[0]).remainingMinutes == 120)
    focus.pause(); expect(focus.dailyProgress(for: todo.tasks[0]).remainingMinutes == 120)
    await focus.resume(); clock = 2400; focus.tick(); focus.tick()
    expect(focus.dailyProgress(for: todo.tasks[0]).remainingMinutes == 80)
    expect(focus.archive.records.count == 1)
    expect(!todo.tasks[0].completed)
    expect(focus.archive.routes.first?.completedCount == 0)
    try focus.toggleStage(first, in: route)
    expect(focus.suggestedStage(for: todo.tasks[0])?.id == second)
    try focus.setLearning(dailyGoal: 120, context: LearningContext(routeID: route, stageID: second), for: todo.tasks[0])
    expect(focus.archive.records.first?.learning?.stageID == first)
    expect(focus.learningContext(for: todo.tasks[0])?.stageID == second)
    await focus.start(todo.tasks[0]); clock += 500; focus.tick(); focus.abandon()
    expect(focus.dailyProgress(for: todo.tasks[0]).remainingMinutes == 80)
    await focus.start(todo.tasks[0]); clock += 400; focus.tick(); focus.reset(); focus.abandon()
    expect(focus.archive.records.count == 1)
    try focus.setLearning(dailyGoal: 20, context: nil, for: todo.tasks[0])
    expect(focus.dailyProgress(for: todo.tasks[0]).remainingMinutes == 0)
    expect(focus.dailyProgress(for: todo.tasks[0]).completedMinutes == 40)
    expect(focus.dailyProgress(for: todo.tasks[0]).reachedGoal)
}

@MainActor func dailyGoalMidnightRestAndInstanceIsolation() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 23, minute: 59))!
    let after = calendar.date(byAdding: .minute, value: 2, to: before)!
    var task = TodoTask(id: "daily", calendarID: "bound", title: "学习", dueDate: before, repeatRule: .daily)
    let firstKey = FocusKey(task: task)
    var engine = FocusEngine()
    engine.start(key: firstKey, minutes: 1, kind: .work, monotonic: 0, date: before)
    engine.tick(monotonic: 120, date: after) // actual end is 00:00, not delayed callback 00:01
    expect(FocusDailyProgress(key: firstKey, goal: 120, records: engine.archive.records, now: before, calendar: calendar).completedMinutes == 0)
    expect(FocusDailyProgress(key: firstKey, goal: 120, records: engine.archive.records, now: after, calendar: calendar).remainingMinutes == 119)
    engine.start(key: firstKey, minutes: 1, kind: .rest, monotonic: 200, date: after)
    engine.tick(monotonic: 260, date: after.addingTimeInterval(60))
    expect(engine.archive.records.count == 1)
    task.dueDate = after
    expect(FocusDailyProgress(key: FocusKey(task: task), goal: 120, records: engine.archive.records, now: after, calendar: calendar).remainingMinutes == 120)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: after)!
    expect(FocusDailyProgress(key: firstKey, goal: 120, records: engine.archive.records, now: tomorrow, calendar: calendar).completedMinutes == 0)
}

@MainActor func learningSettingsRejectUnsafeChangesAndRetainFailedWrites() async throws {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let store = FailingFocusStore()
    let focus = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier())
    try focus.setLearning(dailyGoal: 120, context: nil, for: todo.tasks[0])
    for value in [0, 1441] {
        do { try focus.setLearning(dailyGoal: value, context: nil, for: todo.tasks[0]); expect(false) } catch { }
    }
    expect(focus.dailyGoal(for: todo.tasks[0]) == 120)
    do { try focus.setLearning(dailyGoal: 60, context: LearningContext(routeID: UUID(), stageID: UUID()), for: todo.tasks[0]); expect(false) } catch { }
    await focus.start(todo.tasks[0])
    do { try focus.setLearning(dailyGoal: 60, context: nil, for: todo.tasks[0]); expect(false) } catch { }
    focus.abandon()
    backend.access = .denied
    do { try focus.setLearning(dailyGoal: 60, context: nil, for: todo.tasks[0]); expect(false) } catch { }
    expect(focus.dailyGoal(for: todo.tasks[0]) == 120)
    backend.access = .authorized; store.failSave = true
    do { try focus.setLearning(dailyGoal: 60, context: nil, for: todo.tasks[0]); expect(false) } catch { }
    expect(focus.hasUnsavedArchive)
    expect(focus.dailyGoal(for: todo.tasks[0]) == 60)
    store.failSave = false; focus.retrySave()
    expect(!focus.hasUnsavedArchive)
}

@MainActor func learningArchiveMigratesWithoutInventingHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("Focus.json")
    let legacy = Data(#"{"version":1,"preferences":[{"key":{"calendarID":"bound","taskID":"a","occurrence":"单次"},"minutes":40}],"records":[{"id":"00000000-0000-0000-0000-000000000001","key":{"calendarID":"bound","taskID":"a","occurrence":"单次"},"minutes":40,"completedAt":1000}],"run":{"id":"00000000-0000-0000-0000-000000000002","key":{"calendarID":"bound","taskID":"a","occurrence":"单次"},"kind":"work","minutes":40,"remaining":1800,"running":true,"startedAt":1000},"pendingSummaries":[],"restMinutes":5,"soundEnabled":true}"#.utf8)
    try legacy.write(to: url)
    let store = FileFocusStore(url: url)
    let migrated = try store.load()
    expect(migrated.version == 2)
    expect(migrated.records.count == 1); expect(migrated.records[0].minutes == 40)
    expect(migrated.records[0].learning == nil); expect(migrated.routes.isEmpty)
    expect(migrated.run?.remaining == 1800)
    expect(FocusEngine(archive: migrated).archive.run?.running == false)
    try store.save(migrated)
    let backup = try Data(contentsOf: store.legacyBackupURL); expect(backup == legacy)
    let reloaded = try store.load(); expect(reloaded == migrated)
    let saved = try Data(contentsOf: url)
    try store.save(migrated)
    let unchangedBackup = try Data(contentsOf: store.legacyBackupURL); expect(unchangedBackup == legacy)
    let invalid = Data(#"{"version":2,"preferences":[],"records":[],"pendingSummaries":[],"restMinutes":5,"soundEnabled":true}"#.utf8)
    try invalid.write(to: url)
    do { _ = try store.load(); expect(false) } catch { }
    let retained = try Data(contentsOf: url); expect(retained == invalid)
    try saved.write(to: url)
}

@MainActor func learningSummaryV2PreservesNotesAndRejectsDamage() throws {
    let context = LearningContext(routeID: UUID(), stageID: UUID())
    let daily = FocusDailySummary(day: "2026-10-13", goalMinutes: 120, todayMinutes: 40,
        route: LearningRouteSummary(context: context, routeTitle: "Go\n【小新专注 v9】", stageTitle: "接口", completedStages: 1, totalStages: 3, stageCompleted: false))
    let summary = FocusSummary(minutes: 40, rounds: 1, totalMinutes: 40, lastCompleted: nil, occurrence: "单次", daily: daily)
    let original = "第一行\n中文备注\n\n"
    let written = try FocusNotes.replacing(in: original, summary: summary)
    let parsed = try FocusNotes.parse(written)
    expect(parsed.userNotes == original); expect(parsed.summary?.daily?.goalMinutes == 120)
    expect(parsed.summary?.daily?.todayMinutes == 40); expect(parsed.summary?.daily?.remainingMinutes == 80)
    expect(parsed.summary?.daily?.route?.context == context)
    expect(parsed.summary?.daily?.route?.routeTitle == "Go\n【小新专注 v9】")
    let edited = try FocusNotes.composing(userNotes: "手机改的正文", preserving: written)
    expect(tryParseNotes(edited)?.userNotes == "手机改的正文")
    expect(tryParseNotes(edited)?.summary?.daily == daily)
    for invalid in [written + written, written.replacingOccurrences(of: "今日剩余分钟：80", with: "今日剩余分钟：79"), written.replacingOccurrences(of: "2026-10-13", with: "2026-02-30"), written.replacingOccurrences(of: "【小新专注 v2】", with: "【小新专注 v3】")] {
        do { _ = try FocusNotes.replacing(in: invalid, summary: summary); expect(false) } catch { }
    }
}
@MainActor private func tryParseNotes(_ text: String) -> FocusNotes.Parsed? { try? FocusNotes.parse(text) }

@MainActor func repeatedTaskInheritsLearningButNotTodayAndRefreshesDate() async throws {
    let backend = MemoryBoundary()
    var now = Date(timeIntervalSince1970: 10000); var clock = 0.0
    var task = TodoTask(id: "daily", calendarID: "bound", title: "学习", dueDate: now, revision: "1", repeatRule: .daily)
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), monotonic: { clock }, date: { now })
    let route = try focus.addRoute(title: "Go"); let stage = try focus.addStage(title: "基础", to: route)
    try focus.setLearning(dailyGoal: 120, context: LearningContext(routeID: route, stageID: stage), for: todo.tasks[0])
    focus.setMinutes(40, for: todo.tasks[0]); await focus.start(todo.tasks[0]); now = now.addingTimeInterval(2400); clock = 2400; focus.tick()
    let oldNotes = backend.records[task.id]!.notes
    task = backend.records[task.id]!; task.id = "next-native-id"; task.dueDate = now.addingTimeInterval(86400); task.revision = "new"
    backend.records[task.id] = task
    await todo.refresh()
    expect(focus.dailyGoal(for: task) == 120); expect(focus.minutes(for: task) == 40)
    expect(focus.learningContext(for: task)?.stageID == stage)
    expect(focus.dailyProgress(for: task).completedMinutes == 0)
    focus.tick() // Apple may expose the next instance before the calendar day changes.
    let sameDayNext = try FocusNotes.parse(backend.records[task.id]!.notes)
    expect(sameDayNext.summary?.rounds == 0)
    expect(sameDayNext.summary?.totalMinutes == 0)
    expect(sameDayNext.summary?.daily?.todayMinutes == 0)
    expect(sameDayNext.summary?.occurrence == FocusKey(task: task).occurrence)
    now = now.addingTimeInterval(86400); focus.tick()
    let refreshed = try FocusNotes.parse(backend.records[task.id]!.notes)
    expect(refreshed.summary?.daily?.todayMinutes == 0)
    expect(refreshed.summary?.daily?.day != tryParseNotes(oldNotes)?.summary?.daily?.day)
    expect(focus.archive.records.count == 1)
    // On refresh conflicts, today's local progress remains authoritative and phone text is not overwritten.
    backend.records[task.id]!.notes = "手机并发修改"; backend.records[task.id]!.revision += "external"
    now = now.addingTimeInterval(86400); focus.tick()
    expect(backend.records[task.id]!.notes == "手机并发修改")
    expect(focus.archive.pendingSummaries.contains(FocusKey(task: task)))
    expect(focus.archive.records.count == 1)
}

@MainActor func learningCreationRetriesKeepIdentityAndQueuePhoneUpdates() async throws {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let store = FailingFocusStore()
    let focus = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier())
    let creationID = UUID()
    store.failSave = true
    do { _ = try focus.addRoute(title: "Go", id: creationID); expect(false) } catch { }
    expect(focus.archive.routes.count == 1)
    store.failSave = false
    let route = try focus.addRoute(title: "Go", id: creationID)
    expect(route == creationID); expect(focus.archive.routes.count == 1)
    let stageCreationID = UUID()
    store.failSave = true
    do { _ = try focus.addStage(title: "基础", to: route, id: stageCreationID); expect(false) } catch { }
    store.failSave = false
    let stage = try focus.addStage(title: "基础", to: route, id: stageCreationID)
    expect(stage == stageCreationID); expect(focus.archive.routes[0].stages.count == 1)
    try focus.setLearning(dailyGoal: 120, context: LearningContext(routeID: route, stageID: stage), for: todo.tasks[0])
    store.failSave = true
    do { try focus.toggleStage(stage, in: route); expect(false) } catch { }
    expect(focus.archive.pendingSummaries.contains(FocusKey(task: todo.tasks[0])))
    let oldNotes = backend.records[task.id]!.notes
    expect(tryParseNotes(oldNotes)?.summary?.daily?.route?.stageCompleted == false)
    store.failSave = false; focus.retrySave()
    expect(focus.archive.pendingSummaries.contains(FocusKey(task: todo.tasks[0])))
    focus.retrySummary(for: todo.tasks[0])
    expect(tryParseNotes(backend.records[task.id]!.notes)?.summary?.daily?.route?.stageCompleted == true)
    expect(focus.archive.pendingSummaries.isEmpty)
}

@MainActor func dailyGoal25MinuteRoundsAndMultipleSummaryFailures() async throws {
    let backend = MemoryBoundary()
    for id in ["a", "b"] { backend.records[id] = TodoTask(id: id, calendarID: "bound", title: "学习", revision: "1") }
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    var clock = 0.0
    let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), monotonic: { clock }, date: { Date(timeIntervalSince1970: 10000 + clock) })
    let route = try focus.addRoute(title: "Go"); let stage = try focus.addStage(title: "基础", to: route)
    let context = LearningContext(routeID: route, stageID: stage)
    for task in todo.tasks { try focus.setLearning(dailyGoal: 120, context: context, for: task) }
    var a = todo.tasks.first { $0.id == "a" }!
    await focus.start(a); clock = 1500; focus.tick()
    a = todo.tasks.first { $0.id == "a" }!
    expect(focus.dailyProgress(for: a).remainingMinutes == 95)
    await focus.start(a); clock = 2400; focus.tick()
    expect(focus.dailyProgress(for: a).remainingMinutes == 95)
    focus.abandon()
    // First associated task conflicts; syncing the second must not erase its error.
    todo.tasks.sort { $0.id < $1.id }
    backend.records["a"]!.notes = "手机改过的正文"; backend.records["a"]!.revision += "external"
    try focus.renameRoute(route, title: "Go 新名称")
    expect(focus.archive.pendingSummaries.contains(FocusKey(task: a)))
    expect(focus.errorMessage?.contains("摘要未写入") == true)
    expect(backend.records["a"]!.notes == "手机改过的正文")
    expect(tryParseNotes(backend.records["b"]!.notes)?.summary?.daily?.route?.routeTitle == "Go 新名称")
}

@MainActor func learningBackupFailureAndCorruptSaveNeverOverwriteSource() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = FileFocusStore(url: directory.appendingPathComponent("Focus.json"))
    let legacy = Data(#"{"version":1,"preferences":[],"records":[],"pendingSummaries":[],"restMinutes":12,"soundEnabled":false}"#.utf8)
    try legacy.write(to: store.url)
    let upgraded = try store.load()
    expect(upgraded.restMinutes == 12); expect(!upgraded.soundEnabled)
    let conflicting = Data("existing backup must remain".utf8)
    try conflicting.write(to: store.legacyBackupURL)
    do { try store.save(upgraded); expect(false) } catch { }
    let retained = try Data(contentsOf: store.url); expect(retained == legacy)
    let retainedBackup = try Data(contentsOf: store.legacyBackupURL); expect(retainedBackup == conflicting)
    let corrupt = Data("corrupt source".utf8); try corrupt.write(to: store.url)
    do { try store.save(upgraded); expect(false) } catch { }
    let stillCorrupt = try Data(contentsOf: store.url); expect(stillCorrupt == corrupt)
    let unsupported = Data(#"{"version":3,"preferences":[],"records":[],"pendingSummaries":[],"restMinutes":5,"soundEnabled":true,"routes":[]}"#.utf8)
    try unsupported.write(to: store.url)
    do { _ = try store.load(); expect(false) } catch { }
    let stillUnsupported = try Data(contentsOf: store.url); expect(stillUnsupported == unsupported)
}
