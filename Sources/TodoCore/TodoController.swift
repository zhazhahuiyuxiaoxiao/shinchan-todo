import Foundation
import Combine

public enum ConnectionPhase { case disconnected, chooseAccount, ready, unavailable }

@MainActor public final class TodoController: ObservableObject {
    @Published public var tasks: [TodoTask] = []
    @Published public var accounts: [ReminderAccount] = []
    @Published public var phase: ConnectionPhase = .disconnected
    @Published public var query = TaskQuery()
    @Published public var draft = TaskDraft()
    @Published public var editingTask: TodoTask?
    @Published public var hasEditor = false
    @Published public var loading = false
    @Published public var busy = false
    @Published public var errorMessage: String?
    @Published public var notice: String?
    @Published public var lastWriteSucceeded = false
    @Published public var now = Date()
    public private(set) var calendarID: String?
    private let backend: any ReminderBackend
    private let onBind: (String) -> Void
    private var generation = 0
    public var isDirty: Bool { hasEditor && draft != (editingTask.map(TaskDraft.init(task:)) ?? TaskDraft()) }
    public var visibleTasks: [TodoTask] { query.apply(to: tasks, now: now) }
    public var statistics: TaskStatistics { TaskStatistics(tasks: tasks) }
    public init(backend: any ReminderBackend, calendarID: String? = nil, onBind: @escaping (String) -> Void = { _ in }) {
        self.backend = backend; self.calendarID = calendarID; self.onBind = onBind
    }
    private func service() throws -> ReminderService {
        guard let calendarID, !calendarID.isEmpty else { throw TodoError.missingList }
        return ReminderService(backend: backend, calendarID: calendarID)
    }
    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        if let error = error as? TodoError, [.permission, .missingList, .readOnly].contains(error) {
            phase = calendarID == nil ? .disconnected : .unavailable
            tasks = []
        }
    }
    public func connect() async {
        guard !busy else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            guard try await backend.requestAccess() else { throw TodoError.permission }
            if calendarID != nil { await refresh() }
            else { accounts = try backend.accounts(); phase = .chooseAccount }
        } catch { report(error) }
    }
    public func createList(accountID: String) async {
        guard !busy, phase == .chooseAccount else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            guard backend.access == .authorized else { throw TodoError.permission }
            let id = try backend.createList(in: accountID)
            calendarID = id; onBind(id)
            await refresh()
        } catch { report(error) }
    }
    public func refresh() async {
        guard calendarID != nil else { return }
        generation += 1; let request = generation; let bound = calendarID
        loading = true; now = Date()
        do {
            let tasks = try await service().load()
            guard generation == request, calendarID == bound else { return }
            self.tasks = tasks; phase = .ready; loading = false; errorMessage = nil
            if hasEditor, let editingTask, !isDirty,
               let latest = tasks.first(where: { $0.id == editingTask.id }) {
                self.editingTask = latest; draft = TaskDraft(task: latest)
            }
        } catch {
            guard generation == request, calendarID == bound else { return }
            loading = false; report(error)
        }
    }
    @discardableResult public func beginNew(discardChanges: Bool = false) -> Bool {
        guard !isDirty || discardChanges else { return false }
        editingTask = nil; draft = TaskDraft(); hasEditor = true
        errorMessage = nil; notice = nil; lastWriteSucceeded = false
        return true
    }
    @discardableResult public func select(_ task: TodoTask, discardChanges: Bool = false) -> Bool {
        guard !isDirty || discardChanges else { return false }
        guard task.calendarID == calendarID else { report(TodoError.outsideList); return false }
        editingTask = task; draft = TaskDraft(task: task); hasEditor = true
        errorMessage = nil; notice = nil; lastWriteSucceeded = false
        return true
    }
    public func closeEditor() { hasEditor = false; editingTask = nil; draft = TaskDraft() }
    @discardableResult public func reloadEditor(discardChanges: Bool = false) -> Bool {
        guard !busy, let editingTask, !isDirty || discardChanges else { return false }
        do {
            let latest = try service().reload(editingTask)
            self.editingTask = latest; draft = TaskDraft(task: latest)
            if let index = tasks.firstIndex(where: { $0.id == latest.id }) { tasks[index] = latest }
            errorMessage = nil; notice = nil; lastWriteSucceeded = false
            return true
        } catch { report(error); return false }
    }
    public func save() async {
        guard hasEditor, !busy else { return }
        busy = true; errorMessage = nil; notice = nil; lastWriteSucceeded = false
        defer { busy = false }
        do {
            let service = try service()
            if let editingTask { try service.edit(editingTask, draft: draft) }
            else { _ = try service.add(draft) }
            closeEditor(); lastWriteSucceeded = true
            notice = "已保存到本机提醒事项；手机同步由 iCloud 处理。"
            await refresh()
            if let errorMessage { self.errorMessage = "已保存，但重新加载失败。\(errorMessage)" }
        } catch { report(error) }
    }
    public func toggle(_ task: TodoTask) async {
        guard !busy else { return }
        busy = true; errorMessage = nil; notice = nil; lastWriteSucceeded = false
        defer { busy = false }
        do {
            try service().setCompleted(task, completed: !task.completed)
            lastWriteSucceeded = true; notice = "状态已写入本机提醒事项。"
            await refresh()
            if let errorMessage { self.errorMessage = "状态已保存，但重新加载失败。\(errorMessage)" }
        } catch { report(error) }
    }
    public func delete(_ task: TodoTask) async {
        guard !busy else { return }
        busy = true; errorMessage = nil; notice = nil; lastWriteSucceeded = false
        defer { busy = false }
        do {
            try service().remove(task)
            if editingTask?.id == task.id { closeEditor() }
            lastWriteSucceeded = true; notice = "任务已从本机提醒事项删除，其他设备将由 iCloud 同步。"
            await refresh()
            if let errorMessage { self.errorMessage = "已删除，但重新加载失败。\(errorMessage)" }
        } catch { report(error) }
    }
    public func resetConnection() {
        generation += 1; calendarID = nil; onBind("")
        closeEditor(); tasks = []; accounts = []; phase = .disconnected
        errorMessage = nil; notice = nil; loading = false
    }
    public func refreshClock() { now = Date() }
    public func checkedFocusTask(_ task: TodoTask) throws -> TodoTask {
        let latest = try service().reload(task)
        guard latest.revision == task.revision else { throw TodoError.conflict }
        guard !latest.completed else { throw FocusError.unavailable }
        return latest
    }
    public func currentFocusTask(_ key: FocusKey) throws -> TodoTask {
        let latest = try service().reload(TodoTask(id: key.taskID, calendarID: key.calendarID, title: ""))
        guard !latest.completed, FocusKey(task: latest) == key else { throw FocusError.unavailable }
        return latest
    }
    public func writeFocusSummary(_ task: TodoTask, summary: FocusSummary) throws -> TodoTask {
        guard !busy else { throw FocusError.unavailable }
        let latest = try service().writeFocusSummary(task, summary: summary)
        if let index = tasks.firstIndex(where: { $0.id == latest.id }) { tasks[index] = latest }
        if editingTask?.id == task.id, editingTask?.revision == task.revision {
            // 仅摘要变化才允许推进草稿基准；保存与重读之间的外部编辑不能被默许覆盖。
            var before = task; var after = latest
            before.revision = ""; after.revision = ""
            before.notes = FocusNotes.editableNotes(before.notes)
            after.notes = FocusNotes.editableNotes(after.notes)
            if before == after { editingTask = latest }
        }
        return latest
    }
}
