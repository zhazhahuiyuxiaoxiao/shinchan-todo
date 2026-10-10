import Foundation

public enum RepeatFrequency: String, CaseIterable, Hashable, Sendable {
    case daily, weekly, monthly, yearly
    public var unit: String { switch self { case .daily: "天"; case .weekly: "周"; case .monthly: "月"; case .yearly: "年" } }
    public var title: String { switch self { case .daily: "每天"; case .weekly: "每周"; case .monthly: "每月"; case .yearly: "每年" } }
}
public enum RepeatEnd: Hashable, Sendable { case never, onDate(Date), after(Int) }

/// Only represents patterns which the editor and native adapter can round-trip faithfully.
public struct RepeatSchedule: Hashable, Sendable {
    public var frequency: RepeatFrequency
    public var interval: Int
    public var weekdays: [Int] // Apple weekday numbers: Sunday 1 ... Saturday 7.
    public var monthDays: [Int] // -1 means the last day; 1 ... 31 are fixed dates.
    public var ordinal: Int? // 1 ... 5 or -1, with one weekday in a monthly rule.
    public var end: RepeatEnd
    public init(frequency: RepeatFrequency, interval: Int = 1, weekdays: [Int] = [], monthDays: [Int] = [], ordinal: Int? = nil, end: RepeatEnd = .never) {
        self.frequency = frequency; self.interval = interval; self.weekdays = weekdays.sorted()
        self.monthDays = monthDays.sorted(); self.ordinal = ordinal; self.end = end
    }
    public func validated(start: Date? = nil) throws -> Self {
        guard (1...999).contains(interval), Set(weekdays).count == weekdays.count,
              weekdays.allSatisfy({ (1...7).contains($0) }), Set(monthDays).count == monthDays.count,
              monthDays.allSatisfy({ $0 == -1 || (1...31).contains($0) }) else { throw TodoError.invalidRepeat }
        switch frequency {
        case .daily, .yearly:
            guard weekdays.isEmpty, monthDays.isEmpty, ordinal == nil else { throw TodoError.invalidRepeat }
        case .weekly:
            guard monthDays.isEmpty, ordinal == nil else { throw TodoError.invalidRepeat }
        case .monthly:
            if let ordinal {
                guard (1...5).contains(ordinal) || ordinal == -1,
                      weekdays.count == 1, monthDays.isEmpty else { throw TodoError.invalidRepeat }
            } else { guard weekdays.isEmpty else { throw TodoError.invalidRepeat } }
        }
        switch end {
        case .never: break
        case .after(let count): guard (1...9999).contains(count) else { throw TodoError.invalidRepeat }
        case .onDate(let date):
            guard date.timeIntervalSince1970.isFinite else { throw TodoError.invalidRepeat }
            if let start { guard date >= start else { throw TodoError.invalidRepeat } }
        }
        return self
    }
    public var title: String {
        var parts = [interval == 1 ? frequency.title : "每 \(interval) \(frequency.unit)"]
        if frequency == .weekly && !weekdays.isEmpty {
            if weekdays == [2, 3, 4, 5, 6] { parts.append("工作日") }
            else if weekdays == [1, 7] { parts.append("周末") }
            else { parts.append(weekdays.map(Self.weekdayTitle).joined(separator: "、")) }
        }
        if frequency == .monthly {
            if let ordinal, let day = weekdays.first {
                parts.append((ordinal == -1 ? "最后一个" : "第 \(ordinal) 个") + Self.weekdayTitle(day))
            } else if !monthDays.isEmpty {
                parts.append(monthDays.map { $0 == -1 ? "最后一天" : "\($0) 日" }.joined(separator: "、"))
            }
        }
        switch end {
        case .never: break
        case .after(let count): parts.append("共 \(count) 次")
        case .onDate(let date):
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy/M/d"
            parts.append("至 \(formatter.string(from: date))")
        }
        return parts.joined(separator: " · ")
    }
    /// Calendar arithmetic keeps the selected last day inclusive across DST changes.
    public static func endOfDay(_ day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? day).addingTimeInterval(-1)
    }
    public static func weekdayTitle(_ day: Int) -> String { [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"][day] ?? "未知星期" }
}

public struct TaskRepeat: Hashable, Sendable {
    public let schedule: RepeatSchedule?
    public let unsupportedDescription: String?
    private init(schedule: RepeatSchedule?, unsupported: String?) { self.schedule = schedule; self.unsupportedDescription = unsupported }
    public static let none = TaskRepeat(schedule: nil, unsupported: nil)
    public static let daily = TaskRepeat.scheduled(RepeatSchedule(frequency: .daily))
    public static let other = TaskRepeat.unsupported("未识别的重复规则")
    public static func scheduled(_ schedule: RepeatSchedule) -> Self { Self(schedule: schedule, unsupported: nil) }
    public static func unsupported(_ description: String) -> Self { Self(schedule: nil, unsupported: description) }
    public var isEditable: Bool { unsupportedDescription == nil }
    public var title: String { unsupportedDescription ?? schedule?.title ?? "无" }
}

public enum RepeatPreset: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekends, weekly, biweekly, monthly, yearly, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: "无"; case .daily: "每天"; case .weekdays: "工作日（周一至周五）"; case .weekends: "周末（周六、周日）"
        case .weekly: "每周"; case .biweekly: "每两周"; case .monthly: "每月"; case .yearly: "每年"; case .custom: "自定义"
        }
    }
    public func rule(end: RepeatEnd = .never) -> TaskRepeat {
        switch self {
        case .none: return .none
        case .daily, .custom: return .scheduled(RepeatSchedule(frequency: .daily, end: end))
        case .weekdays: return .scheduled(RepeatSchedule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6], end: end))
        case .weekends: return .scheduled(RepeatSchedule(frequency: .weekly, weekdays: [1, 7], end: end))
        case .weekly: return .scheduled(RepeatSchedule(frequency: .weekly, end: end))
        case .biweekly: return .scheduled(RepeatSchedule(frequency: .weekly, interval: 2, end: end))
        case .monthly: return .scheduled(RepeatSchedule(frequency: .monthly, end: end))
        case .yearly: return .scheduled(RepeatSchedule(frequency: .yearly, end: end))
        }
    }
    public static func matching(_ value: TaskRepeat) -> Self {
        if value == .none { return .none }
        guard var schedule = value.schedule else { return .custom }
        schedule.end = .never
        return allCases.first { $0 != .custom && $0.rule() == .scheduled(schedule) } ?? .custom
    }
}
