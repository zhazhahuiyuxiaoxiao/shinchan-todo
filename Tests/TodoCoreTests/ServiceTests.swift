import Foundation
import TodoCore

@MainActor final class MemoryBoundary: ReminderBackend {
    var access: ReminderAccess = .authorized
    var exists = true
    var writable = true
    var records: [String: TodoTask] = [:]
    var failWrites = false
    var failReads = false
    var invalidRead = false
    var failSingleRead = false
    var lastSingleReadList: String?
    var suspendReads = false
    var pendingReads: [CheckedContinuation<[TodoTask], Error>] = []
    var lastReadList: String?
    var afterUpdate: (() -> Void)?
    func requestAccess() async throws -> Bool { access == .authorized }
    func accounts() throws -> [ReminderAccount] { [] }
    func createList(in accountID: String) throws -> String { "bound" }
    func listExists(_ id: String) -> Bool { exists && id == "bound" }
    func listWritable(_ id: String) -> Bool { writable && id == "bound" }
    func readTasks(in calendarID: String) async throws -> [TodoTask] {
        if suspendReads { return try await withCheckedThrowingContinuation { pendingReads.append($0) } }
        if failReads { throw TodoError.readFailed }
        lastReadList = calendarID
        return records.values.filter { invalidRead || $0.calendarID == calendarID }
    }
    func readTask(id: String, in calendarID: String) throws -> TodoTask? {
        lastSingleReadList = calendarID
        if failSingleRead { throw TodoError.readFailed }
        guard let task = records[id] else { return nil }
        guard task.calendarID == calendarID else { throw TodoError.outsideList }
        return task
    }
    func insert(_ draft: TaskDraft, in calendarID: String) throws -> TodoTask {
        if failWrites { throw TodoError.readOnly }
        let task = TodoTask(id: UUID().uuidString, calendarID: calendarID, title: draft.title, notes: draft.notes, dueDate: draft.dueDate, nativePriority: draft.priority.rawValue, revision: "v1")
        records[task.id] = task; return task
    }
    func update(id: String, in calendarID: String, expectedRevision: String, draft: TaskDraft?, completed: Bool?) throws {
        if failWrites { throw TodoError.readOnly }
        guard var task = records[id] else { throw TodoError.missingTask }
        guard task.calendarID == calendarID else { throw TodoError.outsideList }
        guard task.revision == expectedRevision else { throw TodoError.conflict }
        if let draft { task.title = draft.title; task.notes = draft.notes; task.dueDate = draft.dueDate; task.repeatRule = draft.repeatRule; if task.priority != draft.priority { task.nativePriority = draft.priority.rawValue } }
        if let completed { task.completed = completed }
        task.revision += "x"; records[id] = task; afterUpdate?()
    }
    func delete(id: String, in calendarID: String, expectedRevision: String) throws {
        if failWrites { throw TodoError.readOnly }
        guard let task = records[id] else { throw TodoError.missingTask }
        guard task.calendarID == calendarID else { throw TodoError.outsideList }
        guard task.revision == expectedRevision else { throw TodoError.conflict }
        records.removeValue(forKey: id)
    }
}

@MainActor func movedTaskCannotBeReloadedOrWritten() {
    let (backend, service, task) = fixture()
    backend.records["a"]!.calendarID = "private"
    expectThrows(TodoError.outsideList) { _ = try service.reload(task) }
    expectThrows(TodoError.outsideList) { try service.edit(task, draft: TaskDraft(task: task)) }
    expectThrows(TodoError.outsideList) { try service.setCompleted(task, completed: true) }
    expectThrows(TodoError.outsideList) { try service.remove(task) }
    expect(backend.lastSingleReadList == "bound")
    expect(backend.records["a"]?.calendarID == "private")
}
@MainActor func permissionRevokedWhileReadPendingIsRejected() async {
    let (backend, service, task) = fixture(); backend.suspendReads = true
    let request = Task { await expectThrowsAsync(TodoError.permission) { _ = try await service.load() } }
    while backend.pendingReads.isEmpty { await Task.yield() }
    backend.access = .denied
    backend.pendingReads[0].resume(returning: [task])
    await request.value
}

@MainActor private func fixture() -> (MemoryBoundary, ReminderService, TodoTask) {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "a", calendarID: "bound", title: "原任务", revision: "v1")
    backend.records = ["a": task, "other": TodoTask(id: "other", calendarID: "private", title: "不能操作", revision: "v1")]
    return (backend, ReminderService(backend: backend, calendarID: "bound"), task)
}
@MainActor func readsOnlyBoundList() async throws {
    let (backend, service, _) = fixture()
    let tasks = try await service.load()
    expect(tasks.map(\.id) == ["a"]); expect(backend.lastReadList == "bound")
}
@MainActor func rejectsCrossListResultsAndMutations() async {
    let (backend, service, _) = fixture(); backend.invalidRead = true
    await expectThrowsAsync( TodoError.outsideList) { _ = try await service.load() }
    let outside = backend.records["other"]!
    expectThrows( TodoError.outsideList) { try service.edit(outside, draft: TaskDraft(task: outside)) }
    expectThrows( TodoError.outsideList) { try service.setCompleted(outside, completed: true) }
    expectThrows( TodoError.outsideList) { try service.remove(outside) }
    expect(backend.records["other"] == outside)
}
@MainActor func rejectsStaleEditsCompletionsAndDeletes() {
    let (backend, service, task) = fixture()
    backend.records["a"]!.revision = "v2"; backend.records["a"]!.title = "手机的新标题"
    expectThrows( TodoError.conflict) { try service.edit(task, draft: TaskDraft(task: task)) }
    expectThrows( TodoError.conflict) { try service.setCompleted(task, completed: true) }
    expectThrows( TodoError.conflict) { try service.remove(task) }
    expect(backend.records["a"]?.title == "手机的新标题")
}
@MainActor func rejectsBlankTitleWithoutSavingAndTrimsValidTitle() throws {
    let (backend, service, _) = fixture()
    var draft = TaskDraft(); draft.title = " \n "
    expectThrows( TodoError.emptyTitle) { _ = try service.add(draft) }
    expect(backend.records.count == 2)
    draft.title = "  买牛奶  "
    let saved = try service.add(draft)
    expect(saved.title == "买牛奶"); expect(saved.calendarID == "bound")
}
@MainActor func deniesWritesWhenAccessRevokedOrListMissing() async {
    let (backend, service, task) = fixture(); backend.access = .denied
    await expectThrowsAsync( TodoError.permission) { _ = try await service.load() }
    expectThrows( TodoError.permission) { try service.setCompleted(task, completed: true) }
    backend.access = .authorized; backend.exists = false
    expectThrows( TodoError.missingList) { try service.remove(task) }
    expect(backend.records["a"] == task)
}
@MainActor func preservesOriginalOnWriteFailure() {
    let (backend, service, task) = fixture(); backend.failWrites = true
    var draft = TaskDraft(task: task); draft.title = "新的标题"
    expectThrows( TodoError.readOnly) { try service.edit(task, draft: draft) }
    expect(backend.records["a"] == task)
}
@MainActor func allowsEditsCompletionRestoreAndDeletionInBoundList() throws {
    let (backend, service, task) = fixture()
    var draft = TaskDraft(task: task); draft.title = "新标题"; draft.notes = "说明"
    try service.edit(task, draft: draft)
    let changed = backend.records["a"]!; expect(changed.title == "新标题"); expect(changed.notes == "说明")
    try service.setCompleted(changed, completed: true)
    expect(backend.records["a"]!.completed)
    try service.setCompleted(backend.records["a"]!, completed: false)
    expect(!backend.records["a"]!.completed)
    try service.remove(backend.records["a"]!)
    expect(backend.records["a"] == nil); expect(backend.records["other"] != nil)
}
@MainActor func doesNotChangeAdvancedDateOrNativePriorityWhenEditingNotes() throws {
    let (backend, service, _) = fixture()
    let task = TodoTask(id: "a", calendarID: "bound", title: "重复任务", dueDate: Date(timeIntervalSince1970: 2000), nativePriority: 3, revision: "v1", advancedDate: true)
    backend.records["a"] = task
    var draft = TaskDraft(task: task); draft.notes = "新的说明"
    try service.edit(task, draft: draft)
    expect(backend.records["a"]!.nativePriority == 3)
    let latest = backend.records["a"]!; draft.dueDate = nil
    expectThrows( TodoError.advancedDate) { try service.edit(latest, draft: draft) }
}
