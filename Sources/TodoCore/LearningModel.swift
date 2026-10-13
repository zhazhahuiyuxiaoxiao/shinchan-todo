import Foundation

public struct LearningContext: Codable, Equatable, Hashable, Sendable {
    public let routeID: UUID
    public let stageID: UUID
    public init(routeID: UUID, stageID: UUID) { self.routeID = routeID; self.stageID = stageID }
}

public struct LearningStage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var completedAt: Date?
    public init(id: UUID = UUID(), title: String, completedAt: Date? = nil) {
        self.id = id; self.title = title; self.completedAt = completedAt
    }
}

public struct LearningRoute: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var stages: [LearningStage]
    public init(id: UUID = UUID(), title: String, stages: [LearningStage] = []) {
        self.id = id; self.title = title; self.stages = stages
    }
    public var completedCount: Int { stages.filter { $0.completedAt != nil }.count }
    public var progress: Double { stages.isEmpty ? 0 : Double(completedCount) / Double(stages.count) }
    public func nextStage(after id: UUID) -> LearningStage? {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return nil }
        return stages.dropFirst(index + 1).first(where: { $0.completedAt == nil })
            ?? stages.prefix(index).first(where: { $0.completedAt == nil })
    }
    func validated() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(stages.map(\.id)).count == stages.count,
              stages.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  ($0.completedAt?.timeIntervalSinceReferenceDate.isFinite ?? true) }) else { throw FocusError.invalidFile }
    }
}

public struct FocusDailyProgress: Equatable, Sendable {
    public let goalMinutes: Int?
    public let completedMinutes: Int
    public var remainingMinutes: Int? { goalMinutes.map { max(0, $0 - completedMinutes) } }
    public var reachedGoal: Bool { goalMinutes.map { completedMinutes >= $0 } ?? false }
    public init(key: FocusKey, goal: Int?, records: [FocusRecord], now: Date, calendar: Calendar = .current) {
        goalMinutes = goal
        completedMinutes = FocusStatistics(records: records.filter { $0.key == key }, now: now, calendar: calendar).todayMinutes
    }
    public var title: String {
        guard let goalMinutes, let remainingMinutes else { return "今日已专注 \(completedMinutes) 分钟" }
        return "今日 \(completedMinutes) / \(goalMinutes) 分钟 · " + (reachedGoal ? "今日时长达标" : "剩余 \(remainingMinutes) 分钟")
    }
}

public enum LearningError: LocalizedError {
    case emptyTitle, missingStage, invalidGoal, activeRun, saveFailed
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "请填写路线或阶段名称。"
        case .missingStage: "关联的路线或阶段在这台 Mac 上不可用，请重新选择；历史记录保留。"
        case .invalidGoal: "每日目标请输入 1～1440 的整数分钟。"
        case .activeRun: "这条任务还有未结束的计时，请先结束或放弃，再调整学习设置。"
        case .saveFailed: "学习进度尚未保存，内容保留在内存中，请重试本地保存。"
        }
    }
}
