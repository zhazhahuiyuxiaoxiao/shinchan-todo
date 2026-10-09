import Foundation
import TodoCore

private var localCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}
private func day(_ day: Int, hour: Int = 0) -> Date {
    localCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}
private func item(_ id: String, due: Date? = nil, priority: Int = 0, completed: Bool = false, title: String = "任务", notes: String = "") -> TodoTask {
    TodoTask(id: id, calendarID: "bound", title: title, notes: notes, dueDate: due, nativePriority: priority, completed: completed)
}

@MainActor func todayExcludesCompletedAndOtherDays() {
    var query = TaskQuery(); query.view = .today
    let tasks = [item("today", due: day(9, hour: 23)), item("yesterday", due: day(8)), item("tomorrow", due: day(10)), item("done", due: day(9), completed: true), item("none")]
    expect(query.apply(to: tasks, now: day(9, hour: 12), calendar: localCalendar).map(\.id) == ["today"])
}
@MainActor func overdueUsesCalendarDayNotCurrentHour() {
    var query = TaskQuery(); query.view = .overdue
    let tasks = [item("earlier-today", due: day(9)), item("yesterday", due: day(8, hour: 23)), item("done", due: day(8), completed: true), item("none")]
    expect(query.apply(to: tasks, now: day(9, hour: 18), calendar: localCalendar).map(\.id) == ["yesterday"])
}
@MainActor func midnightUpdatesTheTodayBoundary() {
    var query = TaskQuery(); query.view = .today
    let tasks = [item("old", due: day(9)), item("new", due: day(10))]
    expect(query.apply(to: tasks, now: day(9, hour: 23), calendar: localCalendar).map(\.id) == ["old"])
    expect(query.apply(to: tasks, now: day(10), calendar: localCalendar).map(\.id) == ["new"])
}
@MainActor func combinesStatusPriorityAndCaseInsensitiveNotesSearch() {
    var query = TaskQuery(); query.status = .pending; query.priority = .high; query.search = "  API  "
    let tasks = [item("hit", priority: 3, notes: "检查 api 接口"), item("done", priority: 1, completed: true, notes: "API"), item("low", priority: 9, title: "API"), item("different", priority: 1)]
    expect(query.apply(to: tasks).map(\.id) == ["hit"])
}
@MainActor func sortsDatesThenPriorityAndPlacesUndatedLast() {
    let tasks = [item("none-high", priority: 1), item("tomorrow", due: day(10)), item("today-low", due: day(9), priority: 9), item("today-high", due: day(9), priority: 1), item("yesterday", due: day(8))]
    expect(TaskQuery().apply(to: tasks, calendar: localCalendar).map(\.id) == ["yesterday", "today-high", "today-low", "tomorrow", "none-high"])
}
@MainActor func emptySearchKeepsAllAndCompletedViewFilters() {
    var query = TaskQuery(); query.view = .completed
    expect(query.apply(to: [item("pending"), item("done", completed: true)]).map(\.id) == ["done"])
}
@MainActor func statisticsCountEntireInputAndHaveFiniteEmptyRatio() {
    let stats = TaskStatistics(tasks: [item("a"), item("b", completed: true), item("c", completed: true)])
    expect(stats.total == 3); expect(stats.pending == 1)
    expect(abs(stats.completionRatio - 2.0 / 3.0) < 0.00001)
    let empty = TaskStatistics(tasks: [])
    expect(empty.total == 0); expect(empty.pending == 0); expect(empty.completionRatio == 0)
}
