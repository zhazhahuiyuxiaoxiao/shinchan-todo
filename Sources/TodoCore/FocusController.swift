import Foundation
import Combine

@MainActor public final class FocusController: ObservableObject {
    @Published public private(set) var archive = FocusArchive()
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var notice: String?
    @Published public private(set) var notificationStatus = "尚未启用系统通知"
    @Published public private(set) var storageBlocked = false
    @Published public private(set) var hasUnsavedArchive = false
    public let todo: TodoController
    private var engine = FocusEngine()
    private let store: any FocusStore
    private let notifier: any FocusNotifier
    private let monotonic: () -> Double
    private let date: () -> Date
    private var expectedTasks: [FocusKey: TodoTask] = [:]
    private var lastCheckpoint = -Double.infinity
    public init(todo: TodoController, store: any FocusStore, notifier: any FocusNotifier,
                monotonic: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, date: @escaping () -> Date = Date.init) {
        self.todo = todo; self.store = store; self.notifier = notifier; self.monotonic = monotonic; self.date = date
        notificationStatus = notifier.status
        load()
    }
    public var statistics: FocusStatistics { FocusStatistics(records: archive.records, now: date()) }
    public var displayTime: String {
        let seconds = max(0, Int(ceil(archive.run?.remaining ?? 0)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    public var activeTitle: String { todo.tasks.first(where: { $0.id == archive.run?.key.taskID })?.title ?? "专注任务" }
    public func minutes(for task: TodoTask) -> Int {
        if let preference = archive.preferences.first(where: { $0.key == FocusKey(task: task) }) { return preference.minutes }
        // 下一次原生重复实例可从继承的备注沿用时长；不继承累计轮数。
        return (try? FocusNotes.parse(task.notes).summary?.minutes) ?? 25
    }
    public func load() {
        do {
            let loaded = try store.load().validated()
            engine = FocusEngine(archive: loaded); archive = engine.archive; storageBlocked = false; errorMessage = nil
            if loaded.run?.running == true { notice = "已从最近检查点恢复为暂停；异常退出前最多 5 秒的进度可能未保存。" }
        } catch { storageBlocked = true; errorMessage = error.localizedDescription }
    }
    @discardableResult private func persist() -> Bool {
        archive = engine.archive
        guard !storageBlocked else { return false }
        do { try store.save(archive); lastCheckpoint = monotonic(); hasUnsavedArchive = false; return true }
        catch {
            engine.pause(monotonic: monotonic(), date: date()); archive = engine.archive
            hasUnsavedArchive = true
            notifier.cancel(); errorMessage = "本地专注记录未保存，已暂停计时，内存内容保留。\(error.localizedDescription)"
            return false
        }
    }
    public func retrySave() {
        if storageBlocked { load() } else if persist() { errorMessage = nil; notice = "专注记录已保存到这台 Mac。" }
    }
    public func setMinutes(_ minutes: Int, for task: TodoTask) {
        guard !storageBlocked, (1...180).contains(minutes), archive.run?.key != FocusKey(task: task) || archive.run?.remaining == 0 else { return }
        let key = FocusKey(task: task)
        engine.archive.preferences.removeAll { $0.key == key }
        engine.archive.preferences.append(FocusPreference(key: key, minutes: minutes))
        markPending(key); expectedTasks[key] = task
        if persist() { syncSummary(key, expected: task) }
    }
    public func setRestMinutes(_ minutes: Int) {
        guard !storageBlocked, (1...60).contains(minutes) else { return }
        engine.archive.restMinutes = minutes; _ = persist()
    }
    public func setSound(_ enabled: Bool) async {
        guard !storageBlocked else { return }
        engine.archive.soundEnabled = enabled
        if persist() { await schedule() }
    }
    public func requestNotifications() async {
        await notifier.requestPermission(); notificationStatus = notifier.status
        await schedule()
    }
    public func needsReplacement(for task: TodoTask) -> Bool {
        guard let run = archive.run, run.remaining > 0 else { return false }
        return run.key != FocusKey(task: task) || run.kind == .rest
    }
    public func start(_ task: TodoTask, replace: Bool = false) async {
        guard !storageBlocked else { return }
        do {
            if needsReplacement(for: task), !replace { throw FocusError.activeRun }
            let checked = try todo.checkedFocusTask(task)
            let key = FocusKey(task: checked); let minutes = minutes(for: checked)
            notifier.cancel(); errorMessage = nil; notice = nil
            engine.start(key: key, minutes: minutes, kind: .work, monotonic: monotonic(), date: date())
            expectedTasks[key] = checked; markPending(key)
            if persist() { syncSummary(key, expected: checked); await schedule() }
        } catch { errorMessage = error.localizedDescription }
    }
    public func tick() {
        reconcile()
        let before = engine.archive.records.count
        let previousRun = engine.archive.run
        engine.tick(monotonic: monotonic(), date: date()); archive = engine.archive
        if let run = archive.run, previousRun?.running == true, !run.running, run.remaining == 0 {
            if persist() {
                notifier.finished(run, sound: archive.soundEnabled)
                notice = run.kind == .work ? "这一轮专注完成啦！选择休息、再来一轮，或手动完成任务。" : "休息结束，准备好后再开始下一轮。"
                if archive.records.count > before, let expected = expectedTasks[run.key] { syncSummary(run.key, expected: expected) }
            }
        } else if archive.run?.running == true, monotonic() - lastCheckpoint >= 5 { _ = persist() }
    }
    public func pause() {
        tick(); engine.pause(monotonic: monotonic(), date: date()); notifier.cancel(); _ = persist()
    }
    public func resume() async {
        guard !storageBlocked, let run = archive.run, run.remaining > 0 else { return }
        do {
            guard let task = todo.tasks.first(where: { FocusKey(task: $0) == run.key }) else { throw FocusError.unavailable }
            let checked = try todo.checkedFocusTask(task); expectedTasks[run.key] = checked
            engine.resume(monotonic: monotonic()); errorMessage = nil
            if persist() { await schedule() }
        } catch { errorMessage = error.localizedDescription }
    }
    public func reset() { notifier.cancel(); engine.reset(); notice = nil; _ = persist() }
    public func abandon() { notifier.cancel(); engine.abandon(); notice = nil; _ = persist() }
    public func shutdown() async { pause(); await notifier.shutdown() }
    public func startRest() async {
        guard !storageBlocked, let run = archive.run, run.kind == .work, run.remaining == 0 else { return }
        reconcile(); guard archive.run != nil else { return }
        notifier.cancel()
        engine.start(key: run.key, minutes: archive.restMinutes, kind: .rest, monotonic: monotonic(), date: date())
        notice = nil; if persist() { await schedule() }
    }
    public func reconcile() {
        guard let run = engine.archive.run else { return }
        // 首次连接尚未完成时保留恢复检查点；明确不可用或绑定解除时停止。
        if todo.phase == .unavailable || todo.calendarID != run.key.calendarID ||
            (todo.phase == .ready && !todo.tasks.contains(where: { FocusKey(task: $0) == run.key && !$0.completed })) {
            notifier.cancel(); engine.abandon(); _ = persist()
            notice = "关联任务已完成、删除或不可访问，计时已停止；历史记录保留。"
            return
        }
        if todo.phase == .ready {
            do { _ = try todo.currentFocusTask(run.key) }
            catch {
                notifier.cancel()
                if error as? TodoError == .readFailed {
                    // 暂时读取失败也不继续积累未经验证的专注时间。
                    engine.archive.run?.running = false
                } else { engine.abandon() }
                _ = persist()
                errorMessage = "任务当前无法用于计时，已停止。\(error.localizedDescription)"
            }
        }
    }
    private func markPending(_ key: FocusKey) {
        if !engine.archive.pendingSummaries.contains(key) { engine.archive.pendingSummaries.append(key) }
    }
    public func retrySummary(for task: TodoTask) {
        guard !storageBlocked else { return }
        // UI 明确要求先载入最新核对；checkedFocusTask 仍拒绝旧快照。
        do { let checked = try todo.checkedFocusTask(task); syncSummary(FocusKey(task: checked), expected: checked) }
        catch { errorMessage = "摘要未写入。\(error.localizedDescription)" }
    }
    private func syncSummary(_ key: FocusKey, expected: TodoTask) {
        guard todo.phase == .ready, !storageBlocked else { return }
        do {
            guard FocusKey(task: expected) == key else { throw FocusError.unavailable }
            let records = engine.archive.records.filter { $0.key == key }
            let summary = FocusSummary(minutes: minutes(for: expected), rounds: records.count,
                                       totalMinutes: records.reduce(0) { $0 + $1.minutes }, lastCompleted: records.map(\.completedAt).max(), occurrence: key.occurrence)
            let latest = try todo.writeFocusSummary(expected, summary: summary); expectedTasks[key] = latest
            engine.archive.pendingSummaries.removeAll { $0 == key }
            if persist() { errorMessage = nil }
        } catch { errorMessage = "摘要未写入，本地专注记录保留。\(error.localizedDescription)" }
    }
    private func schedule() async {
        notifier.cancel()
        guard let run = archive.run, run.running else { return }
        do { try await notifier.schedule(run, sound: archive.soundEnabled); notificationStatus = notifier.status }
        catch { notificationStatus = "系统通知安排失败，仍可使用应用内提醒。"; errorMessage = notificationStatus }
    }
}
