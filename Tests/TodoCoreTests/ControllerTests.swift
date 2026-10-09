import Foundation
import TodoCore

@MainActor func explicitReloadFetchesLatestBeforeDiscardingDraft() {
    let backend = MemoryBoundary()
    let old = TodoTask(id: "a", calendarID: "bound", title: "旧缓存", revision: "v1")
    backend.records["a"] = old
    let model = TodoController(backend: backend, calendarID: "bound")
    model.tasks = [old]; _ = model.select(old); model.draft.title = "未保存"
    backend.records["a"]!.title = "后台的新内容"; backend.records["a"]!.revision = "v2"
    expect(!model.reloadEditor()); expect(model.draft.title == "未保存")
    expect(model.reloadEditor(discardChanges: true))
    expect(model.draft.title == "后台的新内容"); expect(model.editingTask?.revision == "v2")
}
@MainActor func failedExplicitReloadRetainsDraft() {
    let backend = MemoryBoundary()
    let old = TodoTask(id: "a", calendarID: "bound", title: "旧内容", revision: "v1")
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.select(old); model.draft.title = "仍然保留"
    expect(!model.reloadEditor(discardChanges: true))
    expect(model.draft.title == "仍然保留"); expect(model.editingTask == old)
    expect(model.errorMessage != nil)
    backend.records["a"] = old; backend.failSingleRead = true
    expect(!model.reloadEditor(discardChanges: true)); expect(model.draft.title == "仍然保留")
    expect(model.editingTask == old)
    backend.access = .denied
    expect(!model.reloadEditor(discardChanges: true)); expect(model.draft.title == "仍然保留")
}
@MainActor func refreshRacesCannotOverwriteLatestState() async {
    let backend = MemoryBoundary(); backend.suspendReads = true
    let model = TodoController(backend: backend, calendarID: "bound")
    let first = Task { await model.refresh() }
    while backend.pendingReads.count < 1 { await Task.yield() }
    let second = Task { await model.refresh() }
    while backend.pendingReads.count < 2 { await Task.yield() }
    backend.pendingReads[1].resume(returning: [TodoTask(id: "new", calendarID: "bound", title: "最新")])
    await second.value
    backend.pendingReads[0].resume(throwing: TodoError.readFailed)
    await first.value
    expect(model.tasks.first?.id == "new"); expect(model.errorMessage == nil); expect(!model.loading)
    let third = Task { await model.refresh() }
    while backend.pendingReads.count < 3 { await Task.yield() }
    model.resetConnection()
    backend.pendingReads[2].resume(returning: [TodoTask(id: "stale", calendarID: "bound", title: "旧请求")])
    await third.value
    expect(model.tasks.isEmpty); expect(model.phase == .disconnected); expect(model.calendarID == nil)
}

@MainActor func failedSaveKeepsDraftAndHasNoSuccessState() async {
    let backend = MemoryBoundary(); backend.failWrites = true
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.beginNew(); model.draft.title = "不能丢失的草稿"; model.draft.notes = "正文"
    await model.save()
    expect(model.hasEditor); expect(model.draft.title == "不能丢失的草稿")
    expect(model.errorMessage != nil); expect(!model.lastWriteSucceeded)
    expect(backend.records.isEmpty)
}
@MainActor func failedRefreshAfterWriteDoesNotInviteDuplicateSubmission() async {
    let backend = MemoryBoundary(); backend.failReads = true
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.beginNew(); model.draft.title = "已写入的任务"
    await model.save()
    expect(backend.records.count == 1); expect(model.lastWriteSucceeded)
    expect(model.errorMessage != nil); expect(!model.hasEditor)
    await model.save()
    expect(backend.records.count == 1)
}
@MainActor func refreshDoesNotOverwriteDirtyEditorOrItsRevision() async {
    let backend = MemoryBoundary()
    let original = TodoTask(id: "a", calendarID: "bound", title: "初始标题", revision: "v1")
    backend.records["a"] = original
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.select(original); model.draft.title = "尚未保存"
    backend.records["a"]!.title = "外部修改"; backend.records["a"]!.revision = "v2"
    await model.refresh()
    expect(model.tasks.first?.title == "外部修改")
    expect(model.draft.title == "尚未保存"); expect(model.editingTask?.revision == "v1")
    await model.save()
    expect(model.errorMessage != nil); expect(model.hasEditor)
    expect(backend.records["a"]?.title == "外部修改")
}
@MainActor func switchingEditorsRequiresExplicitDiscard() {
    let backend = MemoryBoundary(); let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.beginNew(); model.draft.title = "未保存内容"
    let target = TodoTask(id: "a", calendarID: "bound", title: "其他任务")
    expect(!model.select(target)); expect(model.draft.title == "未保存内容")
    expect(model.select(target, discardChanges: true)); expect(model.draft.title == "其他任务")
}
@MainActor func authorizationDenialStopsAtDisconnectedState() async {
    let backend = MemoryBoundary(); backend.access = .denied
    let model = TodoController(backend: backend)
    await model.connect()
    expect(model.phase == .disconnected); expect(model.errorMessage != nil)
    expect(model.accounts.isEmpty); expect(model.tasks.isEmpty)
}
@MainActor func readOnlyListStopsOperationsAndRetainsDraft() async {
    let backend = MemoryBoundary(); backend.writable = false
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.beginNew(); model.draft.title = "草稿"
    await model.refresh(); await model.save()
    expect(model.phase == .unavailable); expect(backend.records.isEmpty)
    expect(model.draft.title == "草稿"); expect(!model.lastWriteSucceeded)
}
