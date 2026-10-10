import Foundation

public enum TaskPriority: Int, CaseIterable, Identifiable, Sendable {
    case none = 0, low = 9, medium = 5, high = 1
    public var id: Int { rawValue }
    public var title: String { switch self { case .none: "无"; case .low: "低"; case .medium: "中"; case .high: "高" } }
    public static func from(native: Int) -> Self {
        switch native { case 1...4: .high; case 5: .medium; case 6...9: .low; default: .none }
    }
    public var rank: Int { switch self { case .none: 0; case .low: 1; case .medium: 2; case .high: 3 } }
}

public struct TodoTask: Identifiable, Equatable, Sendable {
    public var id: String
    public var calendarID: String
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var nativePriority: Int
    public var completed: Bool
    public var createdAt: Date?
    public var revision: String
    public var advancedDate: Bool
    public var repeatRule: TaskRepeat
    public var canEditRepeat: Bool { !completed && repeatRule.isEditable }
    public var priority: TaskPriority { .from(native: nativePriority) }
    public init(id: String, calendarID: String, title: String, notes: String = "", dueDate: Date? = nil,
                nativePriority: Int = 0, completed: Bool = false, createdAt: Date? = nil,
                revision: String = "", advancedDate: Bool = false, repeatRule: TaskRepeat = .none) {
        self.id = id; self.calendarID = calendarID; self.title = title; self.notes = notes
        self.dueDate = dueDate; self.nativePriority = nativePriority; self.completed = completed
        self.createdAt = createdAt; self.revision = revision; self.advancedDate = advancedDate
        self.repeatRule = repeatRule
    }
}

public struct TaskDraft: Equatable, Sendable {
    public var title: String = ""
    public var notes: String = ""
    public var dueDate: Date?
    public var priority: TaskPriority = .none
    public var repeatRule: TaskRepeat = .none
    public var repeatInputError: String?
    public init() {}
    public init(task: TodoTask) { title = task.title; notes = FocusNotes.editableNotes(task.notes); dueDate = task.dueDate; priority = task.priority; repeatRule = task.repeatRule }
    public func validated(for current: TodoTask? = nil) throws -> Self {
        var draft = self
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { throw TodoError.emptyTitle }
        if let current {
            if current.advancedDate && dueDate != current.dueDate { throw TodoError.advancedDate }
            if repeatRule != current.repeatRule && (!current.canEditRepeat || !repeatRule.isEditable) { throw TodoError.repeatReadOnly }
        } else if !repeatRule.isEditable { throw TodoError.repeatReadOnly }
        if repeatInputError != nil { throw TodoError.invalidRepeat }
        if repeatRule != .none && repeatRule != current?.repeatRule {
            guard let dueDate else { throw TodoError.repeatNeedsDate }
            if let schedule = repeatRule.schedule { _ = try schedule.validated(start: dueDate) }
        }
        if current == nil, let schedule = repeatRule.schedule { _ = try schedule.validated(start: dueDate) }
        return draft
    }
}

public enum TaskView: String, CaseIterable, Identifiable, Sendable {
    case all, today, overdue, completed
    public var id: String { rawValue }
    public var title: String { switch self { case .all: "全部任务"; case .today: "今天"; case .overdue: "逾期"; case .completed: "已完成" } }
    public var icon: String { switch self { case .all: "tray.full"; case .today: "sun.max"; case .overdue: "exclamationmark.circle"; case .completed: "checkmark.circle" } }
}
public enum TaskStatus: String, CaseIterable, Identifiable, Sendable {
    case all, pending, completed
    public var id: String { rawValue }
    public var title: String { switch self { case .all: "所有状态"; case .pending: "未完成"; case .completed: "已完成" } }
}
public struct TaskQuery: Sendable {
    public var view: TaskView = .all
    public var status: TaskStatus = .all
    public var priority: TaskPriority?
    public var search: String = ""
    public init() {}
    public func apply(to tasks: [TodoTask], now: Date = Date(), calendar: Calendar = .current) -> [TodoTask] {
        let today = calendar.startOfDay(for: now)
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            switch view {
            case .all: break
            case .completed: if !task.completed { return false }
            case .today:
                guard !task.completed, let due = task.dueDate, calendar.isDate(due, inSameDayAs: today) else { return false }
            case .overdue:
                guard !task.completed, let due = task.dueDate, calendar.startOfDay(for: due) < today else { return false }
            }
            if status == .pending && task.completed { return false }
            if status == .completed && !task.completed { return false }
            if let priority, task.priority != priority { return false }
            return term.isEmpty || task.title.localizedCaseInsensitiveContains(term) || FocusNotes.editableNotes(task.notes).localizedCaseInsensitiveContains(term)
        }.sorted { lhs, rhs in
            let leftDay = lhs.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            let rightDay = rhs.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            if leftDay != rightDay { return leftDay < rightDay }
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank > rhs.priority.rank }
            let leftCreated = lhs.createdAt ?? .distantPast, rightCreated = rhs.createdAt ?? .distantPast
            if leftCreated != rightCreated { return leftCreated < rightCreated }
            return lhs.id < rhs.id
        }
    }
}
public struct TaskStatistics: Equatable, Sendable {
    public let total: Int
    public let pending: Int
    public let completionRatio: Double
    public init(tasks: [TodoTask]) {
        total = tasks.count
        pending = tasks.filter { !$0.completed }.count
        completionRatio = tasks.isEmpty ? 0 : Double(total - pending) / Double(total)
    }
}
