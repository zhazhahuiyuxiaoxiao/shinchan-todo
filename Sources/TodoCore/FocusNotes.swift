import Foundation

public struct LearningRouteSummary: Equatable, Sendable {
    public let context: LearningContext
    public let routeTitle: String
    public let stageTitle: String
    public let completedStages: Int
    public let totalStages: Int
    public let stageCompleted: Bool
    public init(context: LearningContext, routeTitle: String, stageTitle: String, completedStages: Int, totalStages: Int, stageCompleted: Bool) {
        self.context = context; self.routeTitle = routeTitle; self.stageTitle = stageTitle
        self.completedStages = completedStages; self.totalStages = totalStages; self.stageCompleted = stageCompleted
    }
}
public struct FocusDailySummary: Equatable, Sendable {
    public let day: String
    public let goalMinutes: Int?
    public let todayMinutes: Int
    public let route: LearningRouteSummary?
    public var remainingMinutes: Int? { goalMinutes.map { max(0, $0 - todayMinutes) } }
    public init(day: String, goalMinutes: Int?, todayMinutes: Int, route: LearningRouteSummary?) {
        self.day = day; self.goalMinutes = goalMinutes; self.todayMinutes = todayMinutes; self.route = route
    }
}
public struct FocusSummary: Equatable, Sendable {
    public let minutes: Int
    public let rounds: Int
    public let totalMinutes: Int
    public let lastCompleted: Date?
    public let occurrence: String
    public let daily: FocusDailySummary?
    public init(minutes: Int, rounds: Int, totalMinutes: Int, lastCompleted: Date?, occurrence: String, daily: FocusDailySummary? = nil) {
        self.minutes = minutes; self.rounds = rounds; self.totalMinutes = totalMinutes
        self.lastCompleted = lastCompleted; self.occurrence = occurrence; self.daily = daily
    }
}
public enum FocusNotes {
    public static let begin = "【小新专注 v1】"
    public static let beginV2 = "【小新专注 v2】"
    public static let end = "【小新专注结束】"
    public struct Parsed { public let userNotes: String; public let summary: FocusSummary? }
    private static func formatter() -> ISO8601DateFormatter { ISO8601DateFormatter() }
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private static func validDay(_ text: String) -> Bool {
        let parser = DateFormatter(); parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"; parser.isLenient = false
        guard let day = parser.date(from: text) else { return false }
        return parser.string(from: day) == text
    }
    private static let basePrefixes = ["每轮分钟：", "本次任务：", "本机累计轮数：", "本机累计分钟：", "最近完成："]
    private static let dailyPrefixes = ["统计日期：", "今日目标分钟：", "今日完整专注分钟：", "今日剩余分钟：", "学习路线：", "关联阶段：", "阶段进度：", "阶段已打卡：", "关联标识："]
    public static func parse(_ text: String) throws -> Parsed {
        let startCount = text.components(separatedBy: "【小新专注").count - 1
        guard startCount != 0 else { return Parsed(userNotes: text, summary: nil) }
        let marker = text.contains(beginV2) ? beginV2 : begin
        guard startCount == 2,
              text.components(separatedBy: marker).count == 2,
              text.components(separatedBy: end).count == 2,
              let start = text.range(of: marker), let finish = text.range(of: end), start.upperBound <= finish.lowerBound else { throw FocusError.invalidNotes }
        let lines = text[start.upperBound..<finish.lowerBound].split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let prefixes = basePrefixes + (marker == beginV2 ? dailyPrefixes : [])
        guard lines.count == prefixes.count, zip(lines, prefixes).allSatisfy({ $0.hasPrefix($1) }) else { throw FocusError.invalidNotes }
        let values = zip(lines, prefixes).map { String($0.dropFirst($1.count)) }
        guard let minutes = Int(values[0]), (1...180).contains(minutes),
              let rounds = Int(values[2]), rounds >= 0, let total = Int(values[3]), total >= 0,
              values[1] == "单次" || validDay(values[1]) else { throw FocusError.invalidNotes }
        let date = values[4] == "暂无" ? nil : formatter().date(from: values[4])
        guard values[4] == "暂无" || date != nil else { throw FocusError.invalidNotes }
        let daily = marker == beginV2 ? try parseDaily(Array(values.dropFirst(5))) : nil
        guard daily == nil || daily!.todayMinutes <= total else { throw FocusError.invalidNotes }
        var prefix = String(text[..<start.lowerBound])
        if prefix.hasSuffix("\n\n") { prefix.removeLast(2) }
        return Parsed(userNotes: prefix + text[finish.upperBound...], summary: FocusSummary(minutes: minutes, rounds: rounds, totalMinutes: total, lastCompleted: date, occurrence: values[1], daily: daily))
    }
    private static func parseDaily(_ values: [String]) throws -> FocusDailySummary {
        guard validDay(values[0]), let today = Int(values[2]), today >= 0 else { throw FocusError.invalidNotes }
        let goal = values[1] == "未设置" ? nil : Int(values[1])
        guard values[1] == "未设置" || (goal.map { (1...1440).contains($0) } ?? false),
              values[3] == (goal.map { String(max(0, $0 - today)) } ?? "未设置") else { throw FocusError.invalidNotes }
        var route: LearningRouteSummary?
        if values[8] == "未关联" {
            guard Array(values[4...7]) == ["未关联", "未关联", "未关联", "未关联"] else { throw FocusError.invalidNotes }
        } else {
            let ids = values[8].split(separator: "/", omittingEmptySubsequences: false)
            let progress = values[6].split(separator: "/", omittingEmptySubsequences: false)
            guard ids.count == 2, let routeID = UUID(uuidString: String(ids[0])), let stageID = UUID(uuidString: String(ids[1])),
                  progress.count == 2, let completed = Int(progress[0]), let total = Int(progress[1]), total > 0, completed >= 0, completed <= total,
                  values[7] == "是" || values[7] == "否" else { throw FocusError.invalidNotes }
            let decoder = JSONDecoder()
            guard let routeTitle = try? decoder.decode(String.self, from: Data(values[4].utf8)),
                  let stageTitle = try? decoder.decode(String.self, from: Data(values[5].utf8)),
                  !routeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !stageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FocusError.invalidNotes }
            route = LearningRouteSummary(context: LearningContext(routeID: routeID, stageID: stageID), routeTitle: routeTitle, stageTitle: stageTitle,
                                         completedStages: completed, totalStages: total, stageCompleted: values[7] == "是")
        }
        return FocusDailySummary(day: values[0], goalMinutes: goal, todayMinutes: today, route: route)
    }
    private static func quoted(_ text: String) throws -> String {
        let data = try JSONEncoder().encode(text)
        // Titles may contain newlines or reserved markers; escape them without losing the original text.
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "【", with: "\\u3010").replacingOccurrences(of: "】", with: "\\u3011")
    }
    public static func replacing(in text: String, summary: FocusSummary) throws -> String {
        let user = try parse(text).userNotes
        var lines = ["每轮分钟：\(summary.minutes)", "本次任务：\(summary.occurrence)", "本机累计轮数：\(summary.rounds)", "本机累计分钟：\(summary.totalMinutes)", "最近完成：\(summary.lastCompleted.map { formatter().string(from: $0) } ?? "暂无")"]
        if let daily = summary.daily {
            lines += ["统计日期：\(daily.day)", "今日目标分钟：\(daily.goalMinutes.map(String.init) ?? "未设置")", "今日完整专注分钟：\(daily.todayMinutes)", "今日剩余分钟：\(daily.remainingMinutes.map(String.init) ?? "未设置")"]
            if let route = daily.route {
                lines += ["学习路线：\(try quoted(route.routeTitle))", "关联阶段：\(try quoted(route.stageTitle))", "阶段进度：\(route.completedStages)/\(route.totalStages)", "阶段已打卡：\(route.stageCompleted ? "是" : "否")", "关联标识：\(route.context.routeID.uuidString)/\(route.context.stageID.uuidString)"]
            } else { lines += dailyPrefixes.suffix(5).map { $0 + "未关联" } }
        }
        let block = (summary.daily == nil ? begin : beginV2) + "\n" + lines.joined(separator: "\n") + "\n" + end
        _ = try parse(block) // Validate generated metadata before it crosses the system boundary.
        return user + (user.isEmpty ? "" : "\n\n") + block
    }
    public static func composing(userNotes: String, preserving raw: String) throws -> String {
        if let summary = try parse(raw).summary { return try replacing(in: userNotes, summary: summary) }
        return userNotes
    }
    public static func editableNotes(_ raw: String) -> String { (try? parse(raw).userNotes) ?? raw }
}
