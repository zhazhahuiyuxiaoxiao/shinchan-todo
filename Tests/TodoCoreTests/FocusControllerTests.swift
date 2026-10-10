import Foundation
import TodoCore
import TodoSystem

@MainActor final class FailingFocusStore: FocusStore {
    var saved = FocusArchive()
    var failSave = false
    var failLoad = false
    func load() throws -> FocusArchive { if failLoad { throw FocusError.invalidFile }; return saved }
    func save(_ archive: FocusArchive) throws { if failSave { throw TodoError.readOnly }; saved = archive }
}

@MainActor func focusSummaryServiceKeepsDraftAndOriginalFields() throws {
    let backend = MemoryBoundary()
    let original = TodoTask(id: "a", calendarID: "bound", title: "任务", notes: "用户原文", dueDate: Date(), nativePriority: 3, revision: "1", advancedDate: true, repeatRule: .other)
    backend.records[original.id] = original
    let model = TodoController(backend: backend, calendarID: "bound")
    model.tasks = [original]; model.phase = .ready; _ = model.select(original)
    model.draft.title = "尚未保存的标题"; model.draft.notes = "尚未保存的正文"
    let summary = FocusSummary(minutes: 25, rounds: 1, totalMinutes: 25, lastCompleted: nil, occurrence: FocusKey(task: original).occurrence)
    let latest = try model.writeFocusSummary(original, summary: summary)
    expect(model.draft.title == "尚未保存的标题"); expect(model.draft.notes == "尚未保存的正文")
    expect(model.isDirty); expect(model.editingTask?.revision == latest.revision)
    expect(latest.dueDate == original.dueDate); expect(latest.nativePriority == 3); expect(latest.repeatRule == .other)
    try ReminderService(backend: backend, calendarID: "bound").edit(latest, draft: model.draft)
    let parsed = try FocusNotes.parse(backend.records[original.id]!.notes)
    expect(parsed.userNotes == "尚未保存的正文"); expect(parsed.summary == summary)
    expectThrows(.conflict) { _ = try model.writeFocusSummary(original, summary: summary) }
    let outsider = TodoTask(id: "other", calendarID: "private", title: "其他", revision: "1")
    expectThrows(.outsideList) { _ = try model.writeFocusSummary(outsider, summary: summary) }
    backend.access = .denied
    expectThrows(.permission) { _ = try model.writeFocusSummary(latest, summary: summary) }
}

@MainActor func focusControllerCompletionFailureAndRetry() async throws {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", notes: "原文", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let store = FailingFocusStore(); var clock = 0.0
    let focus = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier(), monotonic: { clock }, date: { Date(timeIntervalSince1970: 2000 + clock) })
    focus.setMinutes(1, for: task)
    await focus.start(todo.tasks[0])
    backend.records[task.id]!.notes = "手机改的备注"; backend.records[task.id]!.revision += "x"
    clock = 70; focus.tick(); focus.tick()
    expect(focus.archive.records.count == 1); expect(focus.archive.pendingSummaries.count == 1)
    expect(focus.errorMessage?.contains("摘要未写入") == true)
    expect(backend.records[task.id]!.notes == "手机改的备注")
    await todo.refresh(); focus.retrySummary(for: todo.tasks[0])
    let parsed = try FocusNotes.parse(backend.records[task.id]!.notes)
    expect(parsed.userNotes == "手机改的备注"); expect(parsed.summary?.rounds == 1)
    expect(focus.archive.pendingSummaries.isEmpty); expect(focus.archive.records.count == 1)
    expect(focus.errorMessage == nil)
    await focus.start(todo.tasks[0]); store.failSave = true
    clock += 6; focus.tick()
    expect(focus.archive.run?.running == false); expect(focus.errorMessage != nil)
    expect(focus.hasUnsavedArchive)
    store.failSave = false; focus.retrySave()
    expect(focus.errorMessage == nil)
    expect(!focus.hasUnsavedArchive)
}

@MainActor func focusControllerScopeRecoveryAndTaskLoss() async {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    let store = FailingFocusStore(); var clock = 0.0
    let focus = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier(), monotonic: { clock })
    await focus.start(task); clock = 8; focus.tick()
    let recovered = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier(), monotonic: { clock })
    expect(recovered.archive.run?.running == false); expect(recovered.archive.run?.remaining == 1492)
    backend.records[task.id]!.completed = true; await todo.refresh(); focus.tick()
    expect(focus.archive.run == nil); expect(focus.archive.records.isEmpty)
    await focus.start(todo.tasks[0]); expect(focus.archive.run == nil)
    store.failLoad = true
    let blocked = FocusController(todo: todo, store: store, notifier: DemoFocusNotifier())
    expect(blocked.storageBlocked); await blocked.start(task); expect(blocked.archive.run == nil)
}

@MainActor func focusStopsAfterSuccessfulMutationWithFailedRefresh() async {
    for delete in [false, true] {
        let backend = MemoryBoundary()
        let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
        backend.records[task.id] = task
        let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
        var clock = 0.0
        let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), monotonic: { clock })
        await focus.start(task)
        backend.failReads = true
        if delete { await todo.delete(todo.tasks[0]) } else { await todo.toggle(todo.tasks[0]) }
        expect(todo.lastWriteSucceeded)
        clock = 1600; focus.tick()
        expect(focus.archive.run == nil); expect(focus.archive.records.isEmpty)
    }
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "学习", revision: "1")
    backend.records[task.id] = task
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    var clock = 0.0
    let focus = FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier(), monotonic: { clock })
    await focus.start(task); backend.access = .denied; clock = 1600; focus.tick()
    expect(focus.archive.run == nil); expect(focus.archive.records.isEmpty)
}

@MainActor func focusSummaryRereadCannotAuthorizeOverwritingConcurrentChanges() async throws {
    let backend = MemoryBoundary()
    let original = TodoTask(id: "a", calendarID: "bound", title: "原题", notes: "原备注", revision: "1")
    backend.records[original.id] = original
    let todo = TodoController(backend: backend, calendarID: "bound"); await todo.refresh()
    _ = todo.select(original); todo.draft.title = "Mac 脏草稿"
    backend.afterUpdate = {
        backend.afterUpdate = nil
        backend.records[original.id]!.title = "手机刚刚改的标题"
        backend.records[original.id]!.revision += "external"
    }
    _ = try todo.writeFocusSummary(original, summary: FocusSummary(minutes: 25, rounds: 0, totalMinutes: 0, lastCompleted: nil, occurrence: "单次"))
    expect(todo.editingTask?.revision == original.revision)
    await todo.save()
    expect(todo.hasEditor); expect(todo.draft.title == "Mac 脏草稿")
    expect(backend.records[original.id]?.title == "手机刚刚改的标题")
    expect(!todo.lastWriteSucceeded)
}
