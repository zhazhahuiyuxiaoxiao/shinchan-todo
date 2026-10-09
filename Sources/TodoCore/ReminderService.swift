import Foundation

public enum ReminderAccess: Sendable { case notDetermined, authorized, denied, restricted }
public struct ReminderAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}
public enum TodoError: LocalizedError, Equatable {
    case permission, missingList, readOnly, outsideList, missingTask, conflict, emptyTitle, advancedDate, readFailed, repeatNeedsDate, repeatReadOnly
    public var errorDescription: String? {
        switch self {
        case .permission: "未获得提醒事项权限。请在系统设置的隐私与安全性中允许访问，再刷新。"
        case .missingList: "专用清单无法访问，可能已删除或标识已改变。请重新设置，不会接管同名清单。"
        case .readOnly: "这个清单目前不可写，已停止操作。"
        case .outsideList: "任务不属于绑定清单，已阻止操作。"
        case .missingTask: "这条任务已不存在，草稿仍保留，请刷新后核对。"
        case .conflict: "任务已在其他地方修改。没有覆盖它，草稿仍保留，请重新加载后核对。"
        case .emptyTitle: "请输入任务标题。"
        case .advancedDate: "这条任务含具体时间或重复设置，请在苹果提醒事项中修改日期。"
        case .readFailed: "读取提醒事项失败，请重试。"
        case .repeatNeedsDate: "每天重复需要先设置截止日期，作为第一次任务的日期。"
        case .repeatReadOnly: "已完成、带具体时间或自定义重复的任务，请在苹果提醒事项中管理重复设置；普通已完成任务可先恢复。"
        }
    }
}

/// 系统边界；更新和删除还须在适配器内核对真实记录的清单与版本。
@MainActor public protocol ReminderBackend: AnyObject {
    var access: ReminderAccess { get }
    func requestAccess() async throws -> Bool
    func accounts() throws -> [ReminderAccount]
    func createList(in accountID: String) throws -> String
    func listExists(_ id: String) -> Bool
    func listWritable(_ id: String) -> Bool
    func readTasks(in calendarID: String) async throws -> [TodoTask]
    func readTask(id: String, in calendarID: String) throws -> TodoTask?
    func insert(_ draft: TaskDraft, in calendarID: String) throws -> TodoTask
    func update(id: String, in calendarID: String, expectedRevision: String, draft: TaskDraft?, completed: Bool?) throws
    func delete(id: String, in calendarID: String, expectedRevision: String) throws
}

@MainActor public final class ReminderService {
    public let calendarID: String
    private let backend: any ReminderBackend
    public init(backend: any ReminderBackend, calendarID: String) { self.backend = backend; self.calendarID = calendarID }
    private func checkList() throws {
        guard backend.access == .authorized else { throw TodoError.permission }
        guard backend.listExists(calendarID) else { throw TodoError.missingList }
        guard backend.listWritable(calendarID) else { throw TodoError.readOnly }
    }
    public func reload(_ expected: TodoTask) throws -> TodoTask {
        try checkList()
        guard expected.calendarID == calendarID else { throw TodoError.outsideList }
        guard let task = try backend.readTask(id: expected.id, in: calendarID) else { throw TodoError.missingTask }
        guard task.calendarID == calendarID else { throw TodoError.outsideList }
        return task
    }
    private func latest(_ expected: TodoTask) throws -> TodoTask {
        let task = try reload(expected)
        guard task.revision == expected.revision else { throw TodoError.conflict }
        return task
    }
    public func load() async throws -> [TodoTask] {
        try checkList()
        let tasks = try await backend.readTasks(in: calendarID)
        try checkList()
        guard tasks.allSatisfy({ $0.calendarID == calendarID }) else { throw TodoError.outsideList }
        return tasks
    }
    public func add(_ draft: TaskDraft) throws -> TodoTask {
        try checkList()
        return try backend.insert(draft.validated(), in: calendarID)
    }
    public func edit(_ task: TodoTask, draft: TaskDraft) throws {
        let current = try latest(task)
        let draft = try draft.validated(for: current)
        try backend.update(id: task.id, in: calendarID, expectedRevision: task.revision, draft: draft, completed: nil)
    }
    public func setCompleted(_ task: TodoTask, completed: Bool) throws {
        _ = try latest(task)
        try backend.update(id: task.id, in: calendarID, expectedRevision: task.revision, draft: nil, completed: completed)
    }
    public func remove(_ task: TodoTask) throws {
        _ = try latest(task)
        try backend.delete(id: task.id, in: calendarID, expectedRevision: task.revision)
    }
}
