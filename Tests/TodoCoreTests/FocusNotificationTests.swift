import Foundation
import TodoCore
import TodoSystem

@MainActor final class DelayedNotifications: FocusNotificationTransport {
    var holdAuthorization = false
    var holdAdd = false
    var authContinuation: CheckedContinuation<FocusNotificationAuthorization, Never>?
    var addContinuation: CheckedContinuation<Void, Error>?
    var requestedIDs: [String] = []
    var pending: Set<String> = []
    func authorization() async -> FocusNotificationAuthorization {
        if holdAuthorization { return await withCheckedContinuation { authContinuation = $0 } }
        return .authorized
    }
    func requestPermission() async throws -> Bool { true }
    func add(id: String, delay: Double, kind: FocusKind, sound: Bool) async throws {
        requestedIDs.append(id)
        if holdAdd { try await withCheckedThrowingContinuation { addContinuation = $0 } }
        pending.insert(id)
    }
    func remove(ids: [String]) { pending.subtract(ids) }
}

@MainActor func notificationShutdownDrainsInFlightAndAvoidsDoubleSound() async throws {
    let transport = DelayedNotifications(); transport.holdAdd = true
    var sounds = 0
    let notifier = SystemFocusNotifier(transport: transport, playSound: { sounds += 1 })
    var engine = FocusEngine()
    engine.start(key: FocusKey(task: TodoTask(id: "a", calendarID: "bound", title: "任务")), minutes: 1, kind: .work, monotonic: 0, date: Date())
    let run = engine.archive.run!
    let schedule = Task { try await notifier.schedule(run, sound: true) }
    while transport.addContinuation == nil { await Task.yield() }
    notifier.finished(run, sound: true)
    expect(sounds == 0) // 已提交系统声音请求时不能再播放本机声音。
    var drained = false
    let closing = Task { await notifier.shutdown(); drained = true }
    for _ in 0..<20 { await Task.yield() }
    expect(!drained)
    transport.addContinuation?.resume(); try await schedule.value; await closing.value
    expect(transport.pending.isEmpty)
}

@MainActor func notificationCompletionBeforeAuthorizationPreventsLateAlert() async throws {
    let transport = DelayedNotifications(); transport.holdAuthorization = true
    var sounds = 0
    let notifier = SystemFocusNotifier(transport: transport, playSound: { sounds += 1 })
    var engine = FocusEngine()
    engine.start(key: FocusKey(task: TodoTask(id: "a", calendarID: "bound", title: "任务")), minutes: 1, kind: .work, monotonic: 0, date: Date())
    let run = engine.archive.run!
    let schedule = Task { try await notifier.schedule(run, sound: true) }
    while transport.authContinuation == nil { await Task.yield() }
    notifier.finished(run, sound: true)
    transport.authContinuation?.resume(returning: .authorized); try await schedule.value
    expect(sounds == 1); expect(transport.pending.isEmpty)
}
