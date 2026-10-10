import Foundation
import AppKit
import UserNotifications
import TodoCore

@MainActor public final class DemoFocusNotifier: FocusNotifier {
    public var status = "演示通知 · 不请求系统权限"
    public init() {}
    public func requestPermission() async {}
    public func schedule(_ run: FocusRun, sound: Bool) async throws {}
    public func cancel() {}
    public func finished(_ run: FocusRun, sound: Bool) {}
}

public enum FocusNotificationAuthorization { case authorized, denied, notDetermined }
@MainActor public protocol FocusNotificationTransport: AnyObject {
    func authorization() async -> FocusNotificationAuthorization
    func requestPermission() async throws -> Bool
    func add(id: String, delay: Double, kind: FocusKind, sound: Bool) async throws
    func remove(ids: [String])
}

@MainActor public final class AppleFocusNotificationTransport: FocusNotificationTransport {
    public let center = UNUserNotificationCenter.current()
    public init() { center.removeAllPendingNotificationRequests() }
    public func authorization() async -> FocusNotificationAuthorization {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized ? .authorized : (status == .denied ? .denied : .notDetermined)
    }
    public func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    public func add(id: String, delay: Double, kind: FocusKind, sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = "小新番茄钟"
        content.body = kind == .work ? "这一轮专注结束了，休息一下吧！" : "休息结束了，准备好后再开始。"
        if sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, delay), repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    public func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
}

@MainActor public final class SystemFocusNotifier: NSObject, FocusNotifier, UNUserNotificationCenterDelegate {
    public private(set) var status = "尚未启用系统通知"
    private let transport: any FocusNotificationTransport
    private let playSound: () -> Void
    private var pendingID: String?
    private var scheduledRun: UUID?
    private var generation = 0
    private var closing = false
    private var inFlight: [String: Task<Void, Error>] = [:]
    public init(transport: (any FocusNotificationTransport)? = nil,
                playSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() }) {
        self.transport = transport ?? AppleFocusNotificationTransport(); self.playSound = playSound; super.init()
        if let live = self.transport as? AppleFocusNotificationTransport { live.center.delegate = self }
    }
    public func requestPermission() async {
        do { status = try await transport.requestPermission() ? "系统通知已启用" : "系统通知未获允许；可在系统设置中调整。" }
        catch { status = "请求系统通知失败；可继续计时。" }
    }
    public func schedule(_ run: FocusRun, sound: Bool) async throws {
        guard !closing else { return }
        let token = generation
        let due = Date().addingTimeInterval(run.remaining)
        let authorization = await transport.authorization()
        guard generation == token, !closing else { return }
        guard authorization == .authorized else {
            status = authorization == .denied ? "系统通知被拒绝；应用内提醒仍可用。" : "点击启用通知，可在切换应用时收到提醒。"
            return
        }
        let id = "focus.\(run.id.uuidString).\(token)"
        // 提交前登记，取消能覆盖在途请求；正常退出等待提交结束再删除。
        pendingID = id; scheduledRun = run.id
        let operation = Task { try await transport.add(id: id, delay: due.timeIntervalSinceNow, kind: run.kind, sound: sound) }
        inFlight[id] = operation
        defer { inFlight[id] = nil }
        do { try await operation.value }
        catch {
            if pendingID == id { pendingID = nil; scheduledRun = nil }
            throw error
        }
        guard generation == token else { transport.remove(ids: [id]); return }
        status = "系统通知已启用；实际呈现受系统通知设置影响。"
    }
    public func cancel() {
        generation += 1
        transport.remove(ids: Array(Set(inFlight.keys).union(pendingID.map { [$0] } ?? [])))
        pendingID = nil; scheduledRun = nil
    }
    public func finished(_ run: FocusRun, sound: Bool) {
        if scheduledRun != run.id {
            cancel() // 使尚未返回的权限查询失效，不能在本机提醒后再安排一遍。
            if sound { playSound() }
        }
    }
    public func shutdown() async {
        closing = true; cancel()
        let operations = inFlight
        for operation in operations.values { _ = await operation.result }
        transport.remove(ids: Array(operations.keys))
    }
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            guard notification.request.identifier == self.pendingID else { completionHandler([]); return }
            completionHandler([.banner, .sound])
        }
    }
}
