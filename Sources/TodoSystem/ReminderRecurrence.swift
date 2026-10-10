import Foundation
import EventKit
import TodoCore

public enum ReminderRecurrence {
    public static func read(_ rules: [EKRecurrenceRule]?, hasTime: Bool = false) -> TaskRepeat {
        guard let rules, !rules.isEmpty else { return .none }
        guard rules.count == 1, let rule = rules.first else {
            return .unsupported("\(rules.count) 条重复规则：" + rules.map(describe).joined(separator: "；"))
        }
        let details = describe(rule)
        // EventKit reports the current locale's week start even for simple rules.
        // An explicit different week start cannot be reconstructed via its public initializer.
        let defaultWeekStart = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil).firstDayOfTheWeek
        guard rule.calendarIdentifier == "gregorian", rule.firstDayOfTheWeek == 0 || rule.firstDayOfTheWeek == defaultWeekStart,
              (rule.monthsOfTheYear ?? []).isEmpty, (rule.weeksOfTheYear ?? []).isEmpty,
              (rule.daysOfTheYear ?? []).isEmpty else { return .unsupported(details) }
        let frequency: RepeatFrequency
        switch rule.frequency { case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly; @unknown default: return .unsupported(details) }
        let nativeDays = rule.daysOfTheWeek ?? []
        var ordinal: Int?
        let positions = rule.setPositions ?? []
        if frequency == .monthly, nativeDays.count == 1 {
            if nativeDays[0].weekNumber != 0, positions.isEmpty { ordinal = nativeDays[0].weekNumber }
            else if nativeDays[0].weekNumber == 0, positions.count == 1 { ordinal = positions[0].intValue }
        }
        guard positions.isEmpty || ordinal != nil,
              nativeDays.allSatisfy({ $0.weekNumber == 0 || (nativeDays.count == 1 && ordinal == $0.weekNumber) }) else { return .unsupported(details) }
        let end: RepeatEnd
        if let date = rule.recurrenceEnd?.endDate { end = .onDate(date) }
        else if let limit = rule.recurrenceEnd { end = .after(limit.occurrenceCount) }
        else { end = .never }
        let value = RepeatSchedule(frequency: frequency, interval: rule.interval,
                                   weekdays: nativeDays.map { $0.dayOfTheWeek.rawValue },
                                   monthDays: (rule.daysOfTheMonth ?? []).map(\.intValue), ordinal: ordinal, end: end)
        guard (try? value.validated()) != nil else { return .unsupported(details) }
        return .scheduled(value)
    }
    public static func write(_ value: TaskRepeat) throws -> [EKRecurrenceRule]? {
        guard value.isEditable else { throw TodoError.repeatReadOnly }
        guard let schedule = value.schedule else { return nil }
        let value = try schedule.validated()
        let frequency: EKRecurrenceFrequency
        switch value.frequency { case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly }
        let days = value.weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0)!, weekNumber: value.ordinal ?? 0) }
        let end: EKRecurrenceEnd?
        switch value.end { case .never: end = nil; case .onDate(let date): end = EKRecurrenceEnd(end: date); case .after(let count): end = EKRecurrenceEnd(occurrenceCount: count) }
        return [EKRecurrenceRule(recurrenceWith: frequency, interval: value.interval,
                                 daysOfTheWeek: days.isEmpty ? nil : days,
                                 daysOfTheMonth: value.monthDays.isEmpty ? nil : value.monthDays.map { NSNumber(value: $0) },
                                 monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)]
    }
    private static func describe(_ rule: EKRecurrenceRule) -> String {
        let unit: String
        switch rule.frequency { case .daily: unit = "天"; case .weekly: unit = "周"; case .monthly: unit = "月"; case .yearly: unit = "年"; @unknown default: unit = "未知频率" }
        var parts = ["每 \(rule.interval) \(unit)"]
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            parts.append(days.map { day in
                let name = RepeatSchedule.weekdayTitle(day.dayOfTheWeek.rawValue)
                return day.weekNumber == 0 ? name : (day.weekNumber < 0 ? "倒数 \(-day.weekNumber) 个" : "第 \(day.weekNumber) 个") + name
            }.joined(separator: "、"))
        }
        let extras: [(String, [NSNumber]?)] = [("月内日期", rule.daysOfTheMonth), ("月份", rule.monthsOfTheYear), ("年内周数", rule.weeksOfTheYear), ("年内日期", rule.daysOfTheYear), ("候选位置", rule.setPositions)]
        for (label, values) in extras { if let values, !values.isEmpty { parts.append(label + "：" + values.map { String($0.intValue) }.joined(separator: "、")) } }
        if rule.firstDayOfTheWeek != 0 { parts.append("周起点：" + RepeatSchedule.weekdayTitle(rule.firstDayOfTheWeek)) }
        if rule.calendarIdentifier != "gregorian" { parts.append("历法：" + rule.calendarIdentifier) }
        if let date = rule.recurrenceEnd?.endDate { let formatter = DateFormatter(); formatter.dateFormat = "yyyy/M/d HH:mm"; parts.append("至 \(formatter.string(from: date))") }
        else if let end = rule.recurrenceEnd { parts.append("共 \(end.occurrenceCount) 次") }
        return parts.joined(separator: " · ")
    }
}
