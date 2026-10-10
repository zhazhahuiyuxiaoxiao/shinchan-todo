import Foundation

public struct FocusSummary: Equatable, Sendable {
    public let minutes: Int
    public let rounds: Int
    public let totalMinutes: Int
    public let lastCompleted: Date?
    public let occurrence: String
    public init(minutes: Int, rounds: Int, totalMinutes: Int, lastCompleted: Date?, occurrence: String) {
        self.minutes = minutes; self.rounds = rounds; self.totalMinutes = totalMinutes
        self.lastCompleted = lastCompleted; self.occurrence = occurrence
    }
}
public enum FocusNotes {
    public static let begin = "【小新专注 v1】"
    public static let end = "【小新专注结束】"
    public struct Parsed { public let userNotes: String; public let summary: FocusSummary? }
    private static func formatter() -> ISO8601DateFormatter { ISO8601DateFormatter() }
    public static func parse(_ text: String) throws -> Parsed {
        let startCount = text.components(separatedBy: "【小新专注").count - 1
        guard startCount != 0 else { return Parsed(userNotes: text, summary: nil) }
        guard startCount == 2, // 开始与结束标记各一个。
              text.components(separatedBy: begin).count == 2,
              text.components(separatedBy: end).count == 2,
              let start = text.range(of: begin), let finish = text.range(of: end), start.upperBound <= finish.lowerBound else { throw FocusError.invalidNotes }
        let lines = text[start.upperBound..<finish.lowerBound].split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let prefixes = ["每轮分钟：", "本次任务：", "本机累计轮数：", "本机累计分钟：", "最近完成："]
        guard lines.count == prefixes.count, zip(lines, prefixes).allSatisfy({ $0.hasPrefix($1) }) else { throw FocusError.invalidNotes }
        let values = zip(lines, prefixes).map { String($0.dropFirst($1.count)) }
        guard let minutes = Int(values[0]), (1...180).contains(minutes),
              let rounds = Int(values[2]), rounds >= 0, let total = Int(values[3]), total >= 0,
              values[1] == "单次" || values[1].range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { throw FocusError.invalidNotes }
        let date = values[4] == "暂无" ? nil : formatter().date(from: values[4])
        guard values[4] == "暂无" || date != nil else { throw FocusError.invalidNotes }
        var prefix = String(text[..<start.lowerBound])
        if prefix.hasSuffix("\n\n") { prefix.removeLast(2) }
        return Parsed(userNotes: prefix + text[finish.upperBound...], summary: FocusSummary(minutes: minutes, rounds: rounds, totalMinutes: total, lastCompleted: date, occurrence: values[1]))
    }
    public static func replacing(in text: String, summary: FocusSummary) throws -> String {
        let user = try parse(text).userNotes
        let block = "\(begin)\n每轮分钟：\(summary.minutes)\n本次任务：\(summary.occurrence)\n本机累计轮数：\(summary.rounds)\n本机累计分钟：\(summary.totalMinutes)\n最近完成：\(summary.lastCompleted.map { formatter().string(from: $0) } ?? "暂无")\n\(end)"
        return user + (user.isEmpty ? "" : "\n\n") + block
    }
    public static func composing(userNotes: String, preserving raw: String) throws -> String {
        if let summary = try parse(raw).summary { return try replacing(in: userNotes, summary: summary) }
        return userNotes
    }
    public static func editableNotes(_ raw: String) -> String { (try? parse(raw).userNotes) ?? raw }
}
