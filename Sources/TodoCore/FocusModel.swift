import Foundation

@MainActor public protocol FocusStore: AnyObject {
    func load() throws -> FocusArchive
    func save(_ archive: FocusArchive) throws
}
@MainActor public protocol FocusNotifier: AnyObject {
    var status: String { get }
    func requestPermission() async
    func schedule(_ run: FocusRun, sound: Bool) async throws
    func cancel()
    func finished(_ run: FocusRun, sound: Bool)
    func shutdown() async
}
public extension FocusNotifier { func shutdown() async { cancel() } }

public struct FocusKey: Codable, Hashable, Sendable {
    public let calendarID: String
    public let taskID: String
    public let occurrence: String
    public init(task: TodoTask) {
        calendarID = task.calendarID; taskID = task.id
        if task.repeatRule != .none, let date = task.dueDate {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            occurrence = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        } else { occurrence = "单次" }
    }
}
public enum FocusKind: String, Codable, Sendable { case work, rest }
public struct FocusRun: Codable, Equatable, Sendable {
    public var id = UUID()
    public let key: FocusKey
    public let kind: FocusKind
    public let minutes: Int
    public var remaining: Double
    public var running: Bool
    public let startedAt: Date
    public var learning: LearningContext? = nil
}
public struct FocusRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let key: FocusKey
    public let minutes: Int
    public let completedAt: Date
    public let learning: LearningContext?
    public init(id: UUID, key: FocusKey, minutes: Int, completedAt: Date, learning: LearningContext? = nil) {
        self.id = id; self.key = key; self.minutes = minutes; self.completedAt = completedAt; self.learning = learning
    }
}
public struct FocusPreference: Codable, Equatable, Sendable {
    public let key: FocusKey
    public var minutes: Int
    public var dailyGoalMinutes: Int?
    public var learning: LearningContext?
    public init(key: FocusKey, minutes: Int, dailyGoalMinutes: Int? = nil, learning: LearningContext? = nil) {
        self.key = key; self.minutes = minutes; self.dailyGoalMinutes = dailyGoalMinutes; self.learning = learning
    }
}
public struct FocusArchive: Codable, Equatable, Sendable {
    public var version = 2
    public var preferences: [FocusPreference] = []
    public var records: [FocusRecord] = []
    public var run: FocusRun?
    public var pendingSummaries: [FocusKey] = []
    public var restMinutes = 5
    public var soundEnabled = true
    public var routes: [LearningRoute] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case version, preferences, records, run, pendingSummaries, restMinutes, soundEnabled, routes }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == 1 || version == 2 else { throw FocusError.invalidFile }
        preferences = try values.decode([FocusPreference].self, forKey: .preferences)
        records = try values.decode([FocusRecord].self, forKey: .records)
        run = try values.decodeIfPresent(FocusRun.self, forKey: .run)
        pendingSummaries = try values.decode([FocusKey].self, forKey: .pendingSummaries)
        restMinutes = try values.decode(Int.self, forKey: .restMinutes)
        soundEnabled = try values.decode(Bool.self, forKey: .soundEnabled)
        routes = version == 1 ? [] : try values.decode([LearningRoute].self, forKey: .routes)
    }
    public func upgraded() throws -> Self {
        var result = try validated(); result.version = 2; return result
    }
    public func validated() throws -> Self {
        guard version == 1 || version == 2, (1...60).contains(restMinutes),
              preferences.allSatisfy({ (1...180).contains($0.minutes) && ($0.dailyGoalMinutes.map { (1...1440).contains($0) } ?? true) }),
              records.allSatisfy({ (1...180).contains($0.minutes) }),
              Set(records.map(\.id)).count == records.count,
              Set(preferences.map(\.key)).count == preferences.count else { throw FocusError.invalidFile }
        guard Set(routes.map(\.id)).count == routes.count else { throw FocusError.invalidFile }
        for route in routes { try route.validated() }
        if let run {
            guard (1...(run.kind == .work ? 180 : 60)).contains(run.minutes),
                  run.remaining.isFinite, run.remaining >= 0, run.remaining <= Double(run.minutes * 60),
                  !(run.remaining == 0 && run.running) else { throw FocusError.invalidFile }
        }
        return self
    }
}
public enum FocusError: LocalizedError {
    case invalidFile, invalidNotes, unavailable, activeRun
    public var errorDescription: String? {
        switch self {
        case .invalidFile: "专注记录格式损坏或版本不支持。原文件已保留，停止覆盖，请核对后重试读取。"
        case .invalidNotes: "备注中的小新专注信息无法识别或有多个信息段，已停止摘要写入，原文保留。请在提醒事项中核对。"
        case .unavailable: "只能为绑定清单中已保存、未完成且可访问的任务开始专注。"
        case .activeRun: "另一轮计时尚未结束，请先确认放弃。"
        }
    }
}

/// 所有时间由调用者注入，单调时间只存在内存；恢复时使用检查点并暂停。
public struct FocusEngine {
    public var archive: FocusArchive
    private var anchor: Double?
    public init(archive: FocusArchive = FocusArchive()) {
        self.archive = archive; self.archive.run?.running = false
    }
    public mutating func start(key: FocusKey, minutes: Int, kind: FocusKind, monotonic: Double, date: Date, learning: LearningContext? = nil) {
        archive.run = FocusRun(key: key, kind: kind, minutes: minutes, remaining: Double(minutes * 60), running: true, startedAt: date, learning: learning)
        anchor = monotonic
    }
    public mutating func tick(monotonic: Double, date: Date) {
        guard var run = archive.run, run.running, let anchor else { return }
        let elapsed = max(0, monotonic - anchor)
        run.remaining = max(0, run.remaining - elapsed); self.anchor = monotonic
        if run.remaining == 0 {
            run.running = false; self.anchor = nil
            if run.kind == .work, !archive.records.contains(where: { $0.id == run.id }) {
                // 延迟回调按真正到零时的日期归属，不把午夜前结束计入次日。
                let completion = date.addingTimeInterval(-max(0, elapsed - (archive.run?.remaining ?? 0)))
                archive.records.append(FocusRecord(id: run.id, key: run.key, minutes: run.minutes, completedAt: completion, learning: run.learning))
                if !archive.pendingSummaries.contains(run.key) { archive.pendingSummaries.append(run.key) }
            }
        }
        archive.run = run
    }
    public mutating func pause(monotonic: Double, date: Date) {
        tick(monotonic: monotonic, date: date); archive.run?.running = false; anchor = nil
    }
    public mutating func resume(monotonic: Double) {
        guard let run = archive.run, run.remaining > 0 else { return }
        archive.run?.running = true; anchor = monotonic
    }
    public mutating func reset() {
        guard var run = archive.run else { return }
        run.id = UUID(); run.remaining = Double(run.minutes * 60); run.running = false
        archive.run = run; anchor = nil
    }
    public mutating func abandon() { archive.run = nil; anchor = nil }
}

public struct FocusStatistics {
    public let todayCount: Int
    public let weekCount: Int
    public let todayMinutes: Int
    public let weekMinutes: Int
    public init(records: [FocusRecord], now: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: start)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: start) ?? start
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: monday) ?? tomorrow
        let today = records.filter { $0.completedAt >= start && $0.completedAt < tomorrow && $0.completedAt <= now }
        let week = records.filter { $0.completedAt >= monday && $0.completedAt < weekEnd && $0.completedAt <= now }
        todayCount = today.count; weekCount = week.count
        todayMinutes = today.reduce(0) { $0 + $1.minutes }; weekMinutes = week.reduce(0) { $0 + $1.minutes }
    }
}
