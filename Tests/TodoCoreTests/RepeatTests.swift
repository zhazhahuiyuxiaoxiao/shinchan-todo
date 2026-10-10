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
    expect(ReminderRecurrence.read([daily], hasTime: true) == .daily)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]).schedule?.frequency == .weekly)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil)]).schedule?.interval == 2)
    expect(ReminderRecurrence.read([EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4))]).schedule?.end == .after(4))
    let filtered = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [1], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    expect(!ReminderRecurrence.read([filtered]).isEditable)
    expect(!ReminderRecurrence.read([daily, daily]).isEditable)
    let encoded = try ReminderRecurrence.write(.daily)
    expect(encoded?.count == 1); expect(encoded?.first?.frequency == .daily)
    expect(encoded?.first?.interval == 1); expect(encoded?.first?.recurrenceEnd == nil)
    let disabled = try ReminderRecurrence.write(.none); expect(disabled == nil)
    expectThrows(.repeatReadOnly) { _ = try ReminderRecurrence.write(.other) }
}

// Regression: time-of-day must not hide the repeat frequency.
@MainActor func timedDailyIsStillRecognized() {
    let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
    expect(ReminderRecurrence.read([rule], hasTime: true) == .daily)
}

@MainActor func weeklyRepeatHasUsefulDescription() {
    let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
    expect(ReminderRecurrence.read([rule]).title.contains("2"))
    expect(ReminderRecurrence.read([rule]).title.contains("周"))
}

// These fixtures catch loss of BYDAY, month ordinals, interval and end conditions.
@MainActor func nativeCustomRulesRoundTripWithoutLosingMeaning() throws {
    let weekdays = [2, 4, 6].map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!) }
    let weekly = EKRecurrenceRule(recurrenceWith: .weekly, interval: 3, daysOfTheWeek: weekdays, daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    let parsed = ReminderRecurrence.read([weekly], hasTime: true)
    expect(parsed.isEditable)
    expect(parsed.schedule?.weekdays == [2, 4, 6])
    let saved = try ReminderRecurrence.write(parsed)![0]
    expect(saved.frequency == .weekly && saved.interval == 3)
    expect(saved.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } == [2, 4, 6])
    expect(saved.daysOfTheMonth == nil && saved.recurrenceEnd == nil)

    let monthly = EKRecurrenceRule(recurrenceWith: .monthly, interval: 2, daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(occurrenceCount: 8))
    let monthValue = ReminderRecurrence.read([monthly])
    expect(monthValue.schedule?.ordinal == -1 && monthValue.schedule?.weekdays == [6])
    let monthSaved = try ReminderRecurrence.write(monthValue)![0]
    expect(monthSaved.daysOfTheWeek?.first?.weekNumber == -1)
    expect(monthSaved.recurrenceEnd?.occurrenceCount == 8)

    let end = Date(timeIntervalSince1970: 1798761599)
    let dates = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [4, 19, -1], monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: EKRecurrenceEnd(end: end))
    let datesSaved = try ReminderRecurrence.write(ReminderRecurrence.read([dates]))![0]
    expect(datesSaved.daysOfTheMonth?.map { $0.intValue } == [-1, 4, 19])
    expect(datesSaved.recurrenceEnd?.endDate == end)
    let yearly = try ReminderRecurrence.write(.scheduled(RepeatSchedule(frequency: .yearly, interval: 2)))![0]
    expect(yearly.frequency == .yearly && yearly.interval == 2)
}

@MainActor func unsupportedRecurrenceIsDescribedAndCannotBeReplaced() throws {
    let yearly = EKRecurrenceRule(recurrenceWith: .yearly, interval: 2, daysOfTheWeek: nil, daysOfTheMonth: nil, monthsOfTheYear: [3, 9], weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
    let value = ReminderRecurrence.read([yearly])
    expect(!value.isEditable)
    expect(value.title.contains("2") && value.title.contains("3") && value.title.contains("9"))
    expectThrows(.repeatReadOnly) { _ = try ReminderRecurrence.write(value) }
    let multiple = ReminderRecurrence.read([yearly, yearly])
    expect(!multiple.isEditable && multiple.title.contains("2 条"))
    var task = TodoTask(id: "a", calendarID: "bound", title: "任务", dueDate: Date(), advancedDate: true, repeatRule: value)
    var draft = TaskDraft(task: task); draft.repeatRule = .daily
    expectThrows(.repeatReadOnly) { _ = try draft.validated(for: task) }
    draft = TaskDraft(task: task); draft.notes = "原规则保留"
    let valid = try draft.validated(for: task); expect(valid.repeatRule == value)
    task.completed = true
    draft = TaskDraft(task: task); draft.repeatRule = .none
    expectThrows(.repeatReadOnly) { _ = try draft.validated(for: task) }
}

@MainActor func customRepeatValidationRejectsInvalidFieldsBeforeWrite() {
    var draft = TaskDraft(); draft.title = "学习"
    draft.repeatRule = .scheduled(RepeatSchedule(frequency: .weekly, interval: 2, weekdays: [2, 4]))
    expectThrows(.repeatNeedsDate) { _ = try draft.validated() }
    draft.dueDate = Date(timeIntervalSince1970: 1791583200)
    for bad in [RepeatSchedule(frequency: .daily, interval: 0),
                RepeatSchedule(frequency: .weekly, weekdays: [0]),
                RepeatSchedule(frequency: .monthly, monthDays: [32]),
                RepeatSchedule(frequency: .monthly, weekdays: [2], ordinal: 0),
                RepeatSchedule(frequency: .daily, end: .after(0)),
                RepeatSchedule(frequency: .daily, end: .onDate(Date(timeIntervalSince1970: 0)))] {
        draft.repeatRule = .scheduled(bad)
        expectThrows(.invalidRepeat) { _ = try draft.validated() }
    }
    draft.repeatRule = .daily; draft.repeatInputError = "间隔必须是整数"
    expectThrows(.invalidRepeat) { _ = try draft.validated() }
}

@MainActor func timedRepeatEditingKeepsDateAndSummaryAndConflictDraft() async throws {
    let backend = MemoryBoundary()
    let service = ReminderService(backend: backend, calendarID: "bound")
    let originalDate = Date(timeIntervalSince1970: 1791626400)
    let summary = FocusSummary(minutes: 25, rounds: 2, totalMinutes: 50, lastCompleted: originalDate, occurrence: "2026-10-10")
    let notes = try FocusNotes.replacing(in: "手机写的备注", summary: summary)
    let original = TodoTask(id: "a", calendarID: "bound", title: "学习", notes: notes, dueDate: originalDate, nativePriority: 3, revision: "1", advancedDate: true, repeatRule: .daily)
    backend.records[original.id] = original
    var draft = TaskDraft(task: original)
    draft.repeatRule = .scheduled(RepeatSchedule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6]))
    try service.edit(original, draft: draft)
    let latest = try service.reload(original)
    expect(latest.dueDate == originalDate && latest.nativePriority == 3)
    let parsedNotes = try FocusNotes.parse(latest.notes); expect(parsedNotes.summary == summary)
    // Real controller failure/conflict protection applies to the new structured rule too.
    let controller = TodoController(backend: backend, calendarID: "bound")
    _ = controller.select(latest)
    controller.draft.repeatRule = .scheduled(RepeatSchedule(frequency: .monthly, monthDays: [15]))
    backend.failWrites = true; await controller.save()
    expect(controller.isDirty && controller.draft.repeatRule.schedule?.monthDays == [15])
    expect(!controller.lastWriteSucceeded)
    backend.failWrites = false; backend.records[original.id]!.revision = "phone"
    await controller.save(); expect(controller.isDirty && !controller.lastWriteSucceeded)
}

@MainActor func repeatEndDateIncludesFullDayAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
    let lastMoment = RepeatSchedule.endOfDay(day, calendar: calendar)
    let expected = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 59, second: 59))!
    expect(lastMoment == expected)
    expect(lastMoment.timeIntervalSince(day) == 23 * 3600 - 1)
    let lateTask = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 20))!
    _ = try RepeatSchedule(frequency: .daily, end: .onDate(lastMoment)).validated(start: lateTask)
}

@MainActor func repeatPresetsAndMonthlyPositionMapping() throws {
    let weekdays = try ReminderRecurrence.write(RepeatPreset.weekdays.rule())![0]
    expect(weekdays.frequency == .weekly && weekdays.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } == [2, 3, 4, 5, 6])
    let weekends = try ReminderRecurrence.write(RepeatPreset.weekends.rule())![0]
    expect(weekends.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } == [1, 7])
    let everyOtherWeek = try ReminderRecurrence.write(RepeatPreset.biweekly.rule())![0]
    expect(everyOtherWeek.interval == 2 && everyOtherWeek.daysOfTheWeek == nil)
    let positioned = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.thursday)], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: [3], end: nil)
    let saved = try ReminderRecurrence.write(ReminderRecurrence.read([positioned]))![0]
    expect(saved.daysOfTheWeek?.first?.dayOfTheWeek == .thursday && saved.daysOfTheWeek?.first?.weekNumber == 3)
    let unsupported = EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.tuesday)], daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: [-1], end: nil)
    expect(!ReminderRecurrence.read([unsupported]).isEditable)
    let due = Date(timeIntervalSince1970: 1791583200)
    var first = TodoTask(id: "same", calendarID: "bound", title: "学习", dueDate: due, repeatRule: RepeatPreset.weekdays.rule())
    let initialKey = FocusKey(task: first)
    first.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: due)
    expect(FocusKey(task: first) != initialKey)
}

@MainActor func explicitDraftResetChangesEditorIdentityButBackgroundUpdatesDoNot() async throws {
    let backend = MemoryBoundary()
    let task = TodoTask(id: "same", calendarID: "bound", title: "学习", dueDate: Date(timeIntervalSince1970: 1791583200), revision: "1", advancedDate: true, repeatRule: .daily)
    backend.records[task.id] = task
    let model = TodoController(backend: backend, calendarID: "bound")
    _ = model.select(task)
    let first = model.editorGeneration
    model.draft.repeatInputError = "整数错误"
    await model.refresh()
    expect(model.editorGeneration == first && model.draft.repeatInputError != nil)
    let summary = FocusSummary(minutes: 25, rounds: 0, totalMinutes: 0, lastCompleted: nil, occurrence: "2026-10-10")
    _ = try model.writeFocusSummary(task, summary: summary)
    expect(model.editorGeneration == first && model.draft.repeatInputError != nil)
    expect(model.reloadEditor(discardChanges: true))
    expect(model.editorGeneration > first && model.draft.repeatInputError == nil)
    let reloaded = model.editorGeneration
    model.draft.repeatInputError = "次数错误"
    expect(!model.reloadEditor())
    expect(model.editorGeneration == reloaded && model.draft.repeatInputError != nil)
    backend.failSingleRead = true
    expect(!model.reloadEditor(discardChanges: true))
    expect(model.editorGeneration == reloaded && model.draft.repeatInputError != nil)
    backend.failSingleRead = false
    expect(model.select(backend.records[task.id]!, discardChanges: true))
    expect(model.editorGeneration > reloaded && model.draft.repeatInputError == nil)
    let selected = model.editorGeneration
    expect(model.beginNew(discardChanges: true))
    expect(model.editorGeneration > selected)
    let newGeneration = model.editorGeneration
    model.draft.title = "未保存的新任务"; model.draft.repeatInputError = "整数错误"
    expect(model.beginNew(discardChanges: true))
    expect(model.editorGeneration > newGeneration && model.draft.repeatInputError == nil)
}
