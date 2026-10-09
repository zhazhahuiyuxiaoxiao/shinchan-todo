import Foundation
import EventKit
import TodoCore
import TodoSystem

@MainActor func dailyRequiresDateAndRejectsUnsupportedCreation() {
    let backend = MemoryBoundary()
    let service = ReminderService(backend: backend, calendarID: "bound")
    var draft = TaskDraft(); draft.title = "每天读书"; draft.repeatRule = .daily
    expectThrows(.repeatNeedsDate) { _ = try service.add(draft) }
    draft.repeatRule = .other; draft.dueDate = Date()
    expectThrows(.repeatReadOnly) { _ = try service.add(draft) }

    expect(backend.records.isEmpty)
}

@MainActor func dailyRoundTripAndDisablePreserveDate() async throws {
    let backend = DemoBackend(), service = ReminderService(backend: backend, calendarID: DemoBackend.listID)
    var draft = TaskDraft(); draft.title = "每天读书"; draft.notes = "十分钟"; draft.dueDate = Date(timeIntervalSince1970: 1791504000); draft.repeatRule = .daily
    let saved = try service.add(draft)
    expect(saved.repeatRule == .daily); expect(saved.advancedDate)
    let loaded = try service.reload(saved)
    expect(TaskDraft(task: loaded).repeatRule == .daily)
    var edited = TaskDraft(task: loaded); edited.repeatRule = .none
    try service.edit(loaded, draft: edited)
    let latest = try service.reload(loaded)
    expect(latest.repeatRule == .none); expect(latest.dueDate == draft.dueDate); expect(latest.notes == "十分钟")
    edited.repeatRule = .daily
    try service.edit(latest, draft: edited)
    let enabled = try service.reload(latest); expect(enabled.repeatRule == .daily)
}

@MainActor func repeatChangesRespectAdvancedCompletedConflictAndScope() throws {
    let backend = MemoryBoundary()
    let boundService = ReminderService(backend: backend, calendarID: "bound")
    var task = TodoTask(id: "r", calendarID: "bound", title: "外部任务", dueDate: Date(), revision: "1", advancedDate: true, repeatRule: .other)
    backend.records[task.id] = task
    var draft = TaskDraft(task: task); draft.repeatRule = .daily
    expectThrows(.repeatReadOnly) { try boundService.edit(task, draft: draft) }
    draft = TaskDraft(task: task); draft.notes = "可编辑备注"
    try boundService.edit(task, draft: draft)
    expect(backend.records[task.id]?.repeatRule == .other)
    task.repeatRule = .none; task.advancedDate = false; task.completed = true; backend.records[task.id] = task
    draft = TaskDraft(task: task); draft.repeatRule = .daily
    expectThrows(.repeatReadOnly) { try boundService.edit(task, draft: draft) }
    task.completed = false; backend.records[task.id] = task
    backend.records[task.id]!.revision = "outside"
    expectThrows(.conflict) { try boundService.edit(task, draft: draft) }
    task.calendarID = "private"; backend.records[task.id] = task
    expectThrows(.outsideList) { try boundService.edit(task, draft: draft) }
    expect(backend.records[task.id]?.repeatRule == TaskRepeat.none)
}

@MainActor func repeatDraftSurvivesFailureAndCountsAsDirty() async {
    let backend = MemoryBoundary(); backend.failWrites = true
    let task = TodoTask(id: "r", calendarID: "bound", title: "读书", dueDate: Date(), revision: "1")
    backend.records[task.id] = task
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.select(task); model.draft.repeatRule = .daily
    expect(model.isDirty)
    await model.save()
    expect(model.draft.repeatRule == .daily); expect(model.hasEditor); expect(!model.lastWriteSucceeded)
    expect(backend.records[task.id]?.repeatRule == TaskRepeat.none)
    backend.failWrites = false; backend.records[task.id]!.revision = "phone"
    await model.save()
    expect(model.draft.repeatRule == .daily); expect(model.hasEditor); expect(!model.lastWriteSucceeded)
    expect(backend.records[task.id]?.repeatRule == TaskRepeat.none)
}

@MainActor func nativeRepeatMappingProtectsAdvancedRules() throws {
    expect(ReminderRecurrence.read(nil) == .none)
    let daily = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
    expect(ReminderRecurrence.read([daily]) == .daily)
    expect(ReminderRecurrence.read([daily], hasTime: true) == .other)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]) == .other)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)]) == .other)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4))]) == .other)
    let filtered = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [1], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    expect(ReminderRecurrence.read([filtered]) == .other)
    expect(ReminderRecurrence.read([daily, daily]) == .other)
    let encoded = try ReminderRecurrence.write(.daily)
    expect(encoded?.count == 1); expect(encoded?.first?.frequency == .daily)
    expect(encoded?.first?.interval == 1); expect(encoded?.first?.recurrenceEnd == nil)
    let disabled = try ReminderRecurrence.write(.none); expect(disabled == nil)
    expectThrows(.repeatReadOnly) { _ = try ReminderRecurrence.write(.other) }
}
