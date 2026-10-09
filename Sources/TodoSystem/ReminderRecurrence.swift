import EventKit
import TodoCore

/// 只支持无结束条件、无额外筛选的每天重复，其他规则保持原样。
public enum ReminderRecurrence {
    public static func read(_ rules: [EKRecurrenceRule]?, hasTime: Bool = false) -> TaskRepeat {
        guard let rules, !rules.isEmpty else { return .none }
        guard !hasTime, rules.count == 1, let rule = rules.first,
              rule.frequency == .daily, rule.interval == 1, rule.recurrenceEnd == nil,
              (rule.daysOfTheWeek ?? []).isEmpty, (rule.daysOfTheMonth ?? []).isEmpty,
              (rule.monthsOfTheYear ?? []).isEmpty, (rule.weeksOfTheYear ?? []).isEmpty,
              (rule.daysOfTheYear ?? []).isEmpty, (rule.setPositions ?? []).isEmpty else { return .other }
        return .daily
    }
    public static func write(_ value: TaskRepeat) throws -> [EKRecurrenceRule]? {
        switch value {
        case .none: return nil
        case .daily: return [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)]
        case .other: throw TodoError.repeatReadOnly
        }
    }
}
