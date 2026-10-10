import Foundation
@preconcurrency import EventKit
import TodoCore

@MainActor public final class EventKitBackend: ReminderBackend {
    private lazy var store = EKEventStore()
    public init() {}
    public var access: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess: .authorized
        case .restricted: .restricted
        default: .denied
        }
    }
    public func requestAccess() async throws -> Bool {
        if access == .authorized { return true }
        guard access == .notDetermined else { return false }
        return try await store.requestFullAccessToReminders()
    }
    private func requireAccess() throws {
        guard access == .authorized else { throw TodoError.permission }
    }
    public func accounts() throws -> [ReminderAccount] {
        try requireAccess()
        let calendars = store.calendars(for: .reminder)
        return store.sources.filter { source in
            source.sourceType == .calDAV && calendars.contains { $0.source.sourceIdentifier == source.sourceIdentifier && $0.allowsContentModifications }
        }.map { ReminderAccount(id: $0.sourceIdentifier, title: $0.title) }.sorted { $0.title < $1.title }
    }
    public func createList(in accountID: String) throws -> String {
        try requireAccess()
        guard try accounts().contains(where: { $0.id == accountID }),
              let source = store.source(withIdentifier: accountID) else { throw TodoError.readOnly }
        let titles = Set(store.calendars(for: .reminder).filter { $0.source.sourceIdentifier == accountID }.map(\.title))
        let base = "小新待办"; var title = base; var suffix = 2
        while titles.contains(title) { title = "\(base)（\(suffix)）"; suffix += 1 }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.source = source; calendar.title = title
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }
    public func listExists(_ id: String) -> Bool {
        guard access == .authorized else { return false }
        return store.calendar(withIdentifier: id)?.allowedEntityTypes.contains(.reminder) == true
    }
    public func listWritable(_ id: String) -> Bool {
        guard access == .authorized else { return false }
        return store.calendar(withIdentifier: id)?.allowsContentModifications == true
    }
    private func checkedCalendar(_ id: String) throws -> EKCalendar {
        try requireAccess()
        guard let calendar = store.calendar(withIdentifier: id), calendar.allowedEntityTypes.contains(.reminder) else { throw TodoError.missingList }
        guard calendar.allowsContentModifications else { throw TodoError.readOnly }
        return calendar
    }
    public func readTasks(in calendarID: String) async throws -> [TodoTask] {
        let calendar = try checkedCalendar(calendarID)
        let predicate = store.predicateForReminders(in: [calendar])
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                Task { @MainActor in
                    do {
                        guard let self else { throw TodoError.readFailed }
                        _ = try self.checkedCalendar(calendarID)
                        guard let reminders else { throw TodoError.readFailed }
                        guard reminders.allSatisfy({ $0.calendar.calendarIdentifier == calendarID }) else { throw TodoError.outsideList }
                        continuation.resume(returning: try reminders.map(self.snapshot))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
    public func readTask(id: String, in calendarID: String) throws -> TodoTask? {
        _ = try checkedCalendar(calendarID)
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh() else { return nil }
        guard reminder.calendar.calendarIdentifier == calendarID else { throw TodoError.outsideList }
        return try snapshot(reminder)
    }
    private struct Revision: Encodable {
        let title: String
        let notes: String
        let dates: DateComponents?
        let start: DateComponents?
        let priority: Int
        let completed: Bool
        let modified: Date?
        let repeats: [String]
    }
    private func snapshot(_ reminder: EKReminder) throws -> TodoTask {
        let components = reminder.dueDateComponents
        let hasTime = [components, reminder.startDateComponents].contains { $0?.hour != nil || $0?.minute != nil || $0?.second != nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components?.timeZone ?? .current
        let dueDate = components.flatMap { calendar.date(from: $0) }
        let repeats = (reminder.recurrenceRules ?? []).map { rule in
            [rule.calendarIdentifier, String(rule.frequency.rawValue), String(rule.interval), String(rule.firstDayOfTheWeek),
             String(describing: rule.recurrenceEnd?.endDate), String(describing: rule.recurrenceEnd?.occurrenceCount),
             (rule.daysOfTheWeek ?? []).map { "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)" }.joined(separator: ","),
             String(describing: rule.daysOfTheMonth), String(describing: rule.monthsOfTheYear),
             String(describing: rule.weeksOfTheYear), String(describing: rule.daysOfTheYear),
             String(describing: rule.setPositions)].joined(separator: "|")
        }
        let revision = Revision(title: reminder.title ?? "", notes: reminder.notes ?? "", dates: components,
                                start: reminder.startDateComponents, priority: reminder.priority,
                                completed: reminder.isCompleted, modified: reminder.lastModifiedDate, repeats: repeats)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return TodoTask(id: reminder.calendarItemIdentifier, calendarID: reminder.calendar.calendarIdentifier,
                        title: revision.title, notes: revision.notes, dueDate: dueDate, nativePriority: reminder.priority,
                        completed: reminder.isCompleted, createdAt: reminder.creationDate,
                        revision: try encoder.encode(revision).base64EncodedString(),
                        advancedDate: hasTime || reminder.hasRecurrenceRules,
                        repeatRule: ReminderRecurrence.read(reminder.recurrenceRules, hasTime: hasTime))
    }
    private func dateComponents(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.calendar = calendar; components.timeZone = nil
        return components
    }
    public func insert(_ draft: TaskDraft, in calendarID: String) throws -> TodoTask {
        let calendar = try checkedCalendar(calendarID)
        let draft = try draft.validated()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar; reminder.title = draft.title
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        reminder.dueDateComponents = dateComponents(draft.dueDate); reminder.priority = draft.priority.rawValue
        reminder.recurrenceRules = try ReminderRecurrence.write(draft.repeatRule)
        try store.save(reminder, commit: true)
        return try snapshot(reminder)
    }
    private func checkedTask(_ id: String, in calendarID: String, revision: String) throws -> EKReminder {
        _ = try checkedCalendar(calendarID)
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh() else { throw TodoError.missingTask }
        guard reminder.calendar.calendarIdentifier == calendarID else { throw TodoError.outsideList }
        guard try snapshot(reminder).revision == revision else { throw TodoError.conflict }
        return reminder
    }
    public func update(id: String, in calendarID: String, expectedRevision: String, draft: TaskDraft?, completed: Bool?) throws {
        let reminder = try checkedTask(id, in: calendarID, revision: expectedRevision)
        let current = try snapshot(reminder)
        if let draft {
            let draft = try draft.validated(for: current)
            if current.title != draft.title { reminder.title = draft.title }
            if current.notes != draft.notes { reminder.notes = draft.notes.isEmpty ? nil : draft.notes }
            if current.dueDate != draft.dueDate { reminder.dueDateComponents = dateComponents(draft.dueDate) }
            if current.priority != draft.priority { reminder.priority = draft.priority.rawValue }
            if current.repeatRule != draft.repeatRule { reminder.recurrenceRules = try ReminderRecurrence.write(draft.repeatRule) }
        }
        if let completed { reminder.isCompleted = completed }
        try store.save(reminder, commit: true)
    }
    public func delete(id: String, in calendarID: String, expectedRevision: String) throws {
        let reminder = try checkedTask(id, in: calendarID, revision: expectedRevision)
        try store.remove(reminder, commit: true)
    }
}
