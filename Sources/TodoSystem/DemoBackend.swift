import Foundation
import TodoCore

/// 明确标识的纯内存演示；不实例化 EKEventStore、不读取真实任务或偏好绑定。
@MainActor public final class DemoBackend: ReminderBackend {
    public static let listID = "demo-only"
    private var tasks: [String: TodoTask] = [:]
    private var revision = 1
    public init() {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        let seeds: [(String, String, Int, Int?, Bool)] = [
            ("整理 Go 项目的下一步", "把接口、权限与失败路径记录清楚。", 1, 0, false),
            ("下班后买牛奶", "顺便带一盒巧克力饼干。", 5, 0, false),
            ("读完一章技术书", "读一点，再亲手试一点。", 9, 1, false),
            ("给旧项目补一份说明", "先写清楚当前边界。", 1, -1, false),
            ("散步十分钟", "小小休息，也算完成一件事。", 0, nil, true)
        ]
        for (index, seed) in seeds.enumerated() {
            let id = "demo-\(index)"
            tasks[id] = TodoTask(id: id, calendarID: Self.listID, title: seed.0, notes: seed.1,
                                 dueDate: seed.3.flatMap { calendar.date(byAdding: .day, value: $0, to: today) },
                                 nativePriority: seed.2, completed: seed.4, createdAt: today,
                                 revision: "demo-1")
        }
    }
    public var access: ReminderAccess { .authorized }
    public func requestAccess() async throws -> Bool { true }
    public func accounts() throws -> [ReminderAccount] { [] }
    public func createList(in accountID: String) throws -> String { throw TodoError.readOnly }
    public func listExists(_ id: String) -> Bool { id == Self.listID }
    public func listWritable(_ id: String) -> Bool { id == Self.listID }
    public func readTasks(in calendarID: String) async throws -> [TodoTask] {
        guard listExists(calendarID) else { throw TodoError.missingList }
        return Array(tasks.values)
    }
    public func readTask(id: String, in calendarID: String) throws -> TodoTask? {
        guard let task = tasks[id] else { return nil }
        guard task.calendarID == calendarID else { throw TodoError.outsideList }
        return task
    }
    public func insert(_ draft: TaskDraft, in calendarID: String) throws -> TodoTask {
        guard listExists(calendarID) else { throw TodoError.missingList }
        let draft = try draft.validated()
        let task = TodoTask(id: UUID().uuidString, calendarID: calendarID, title: draft.title, notes: draft.notes, dueDate: draft.dueDate,
                            nativePriority: draft.priority.rawValue, createdAt: Date(), revision: nextRevision(), advancedDate: draft.repeatRule != .none, repeatRule: draft.repeatRule)
        tasks[task.id] = task; return task
    }
    private func nextRevision() -> String { revision += 1; return "demo-\(revision)" }
    private func current(_ id: String, _ calendarID: String, _ expected: String) throws -> TodoTask {
        guard let task = tasks[id] else { throw TodoError.missingTask }
        guard task.calendarID == calendarID, calendarID == Self.listID else { throw TodoError.outsideList }
        guard task.revision == expected else { throw TodoError.conflict }
        return task
    }
    public func update(id: String, in calendarID: String, expectedRevision: String, draft: TaskDraft?, completed: Bool?) throws {
        var task = try current(id, calendarID, expectedRevision)
        if let draft {
            let draft = try draft.validated(for: task)
            task.title = draft.title; task.notes = draft.notes; task.dueDate = draft.dueDate; task.nativePriority = draft.priority.rawValue
            task.repeatRule = draft.repeatRule; task.advancedDate = draft.repeatRule != .none
        }
        if let completed { task.completed = completed }
        task.revision = nextRevision(); tasks[id] = task
    }
    public func delete(id: String, in calendarID: String, expectedRevision: String) throws {
        _ = try current(id, calendarID, expectedRevision); tasks.removeValue(forKey: id)
    }
}
