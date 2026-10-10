import SwiftUI
import TodoCore

struct FocusCard: View {
    @ObservedObject var focus: FocusController
    let task: TodoTask
    @State private var replace = false
    @State private var workText: String
    @State private var restText: String
    @State private var invalidFields: Set<DurationField> = []
    @FocusState private var durationFocused: DurationField?
    private enum DurationField: Hashable { case work, rest }
    init(focus: FocusController, task: TodoTask) {
        self.focus = focus; self.task = task
        _workText = State(initialValue: String(focus.minutes(for: task)))
        _restText = State(initialValue: String(focus.archive.restMinutes))
    }
    private var active: Bool { focus.archive.run?.key == FocusKey(task: task) }
    private var locked: Bool { active && (focus.archive.run?.remaining ?? 0) > 0 }
    private var restLocked: Bool { focus.archive.run?.kind == .rest && (focus.archive.run?.remaining ?? 0) > 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("给这件小事一点专注时间", systemImage: "timer").font(.system(size: 14, weight: .bold))
            durationInput("专注", field: .work, text: $workText, range: 1...180,
                          disabled: locked || task.completed || focus.storageBlocked)
            durationInput("休息", field: .rest, text: $restText, range: 1...60,
                          disabled: restLocked || focus.storageBlocked)
            Text("可直接输入分钟数，按回车或离开输入框保存，也可用加减按钮调整。")
                .font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true)
            if active, let run = focus.archive.run {
                HStack {
                    Text(run.kind == .work ? "本轮专注" : "短休息").font(.caption)
                    Spacer()
                    Text(focus.displayTime).font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                }
                if run.remaining > 0 {
                    HStack {
                        Button(run.running ? "暂停" : "继续") { if run.running { focus.pause() } else { Task { await focus.resume() } } }
                            .buttonStyle(CrayonButton(fill: Crayon.yellow))
                        Button("重置") { focus.reset() }.buttonStyle(CrayonButton(fill: Crayon.paper))
                    }
                } else {
                    Text("计时已结束，任务完成状态由你决定。").font(.caption).foregroundStyle(Crayon.muted)
                    if run.kind == .work {
                        Button("开始短休息") { if commit(.rest) { durationFocused = nil; Task { await focus.startRest() } } }.buttonStyle(CrayonButton(fill: Crayon.sky))
                        Button("完成这条任务") { Task { await focus.todo.toggle(task) } }.disabled(focus.todo.isDirty || focus.todo.busy || task.completed)
                    }
                }
            }
            if !locked {
                Button(active ? "再来一轮" : "开始专注") {
                    guard commitDurations() else { return }
                    if focus.needsReplacement(for: task) { replace = true } else { startFocus() }
                }.buttonStyle(CrayonButton(fill: Crayon.red, foreground: .white)).disabled(task.completed || focus.storageBlocked || focus.todo.busy)
            }
            if focus.archive.pendingSummaries.contains(FocusKey(task: task)) {
                Text("摘要未写入。请先载入最新任务核对，再重试。").font(.caption).foregroundStyle(Crayon.red)
                Button("重试写入摘要") { focus.retrySummary(for: task) }.disabled(focus.todo.isDirty || task.completed)
            }
            Text("手机在提醒事项备注中查看摘要；完整记录保存在这台 Mac。").font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true)
        }.paperPanel()
        .onDisappear { _ = commit(.work); _ = commit(.rest) }
        .onChange(of: durationFocused) { previous, _ in if let previous { _ = commit(previous) } }
        .onChange(of: focus.minutes(for: task)) { _, value in
            if durationFocused != .work && !invalidFields.contains(.work) { workText = String(value) }
        }
        .onChange(of: focus.archive.restMinutes) { _, value in
            if durationFocused != .rest && !invalidFields.contains(.rest) { restText = String(value) }
        }
        .alert("放弃当前未结束的计时？", isPresented: $replace) {
            Button("继续原计时", role: .cancel) {}
            Button("放弃并开始", role: .destructive) { if commitDurations() { startFocus(replace: true) } }
        } message: { Text("当前未完成的一轮不会计入统计，历史记录保留。") }
    }
    private func durationInput(_ title: String, field: DurationField, text: Binding<String>, range: ClosedRange<Int>, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                TextField("分钟", text: text).textFieldStyle(.roundedBorder).frame(width: 64)
                    .multilineTextAlignment(.trailing).focused($durationFocused, equals: field)
                    .accessibilityLabel("\(title)时长（分钟）")
                    .onSubmit { if commit(field) { durationFocused = nil } }
                Text("分钟").font(.caption)
                Spacer(minLength: 0)
                Stepper(title, value: Binding(get: {
                    FocusDurationInput.minutes(from: text.wrappedValue, in: range) ?? savedMinutes(field)
                }, set: { value in
                    text.wrappedValue = String(value); _ = commit(field)
                }), in: range).labelsHidden().fixedSize().accessibilityLabel("调整\(title)时长")
            }.disabled(disabled)
            if invalidFields.contains(field) {
                Text("请输入 \(range.lowerBound)～\(range.upperBound) 的整数分钟，已保存时长未改变。")
                    .font(.caption).foregroundStyle(Crayon.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func savedMinutes(_ field: DurationField) -> Int {
        field == .work ? focus.minutes(for: task) : focus.archive.restMinutes
    }
    @discardableResult private func commit(_ field: DurationField) -> Bool {
        if focus.storageBlocked || (field == .work && (locked || task.completed)) || (field == .rest && restLocked) { return true }
        let text = field == .work ? workText : restText
        guard let value = FocusDurationInput.minutes(from: text, in: field == .work ? 1...180 : 1...60) else {
            invalidFields.insert(field); return false
        }
        invalidFields.remove(field)
        if field == .work { workText = String(value) } else { restText = String(value) }
        if value != savedMinutes(field) {
            if field == .work { focus.setMinutes(value, for: task) } else { focus.setRestMinutes(value) }
        }
        return true
    }
    private func commitDurations() -> Bool {
        let workValid = commit(.work); let restValid = commit(.rest)
        guard workValid && restValid else { durationFocused = workValid ? .rest : .work; return false }
        durationFocused = nil; return true
    }
    private func startFocus(replace: Bool = false) {
        // 保存时长可能只更新了摘要及编辑版本，使用控制器保留的当前编辑快照。
        let current = focus.todo.editingTask.flatMap { FocusKey(task: $0) == FocusKey(task: task) ? $0 : nil } ?? task
        Task { await focus.start(current, replace: replace) }
    }

}

struct FocusBar: View {
    @ObservedObject var focus: FocusController
    @State private var abandon = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { current; Spacer(minLength: 8); statistics; controls }
                VStack(alignment: .leading, spacing: 10) { current; HStack { statistics; Spacer(); controls } }
            }
            Text(focus.notificationStatus).font(.caption2).foregroundStyle(Crayon.muted)
            if let notice = focus.notice { Text(notice).font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true) }
            if let error = focus.errorMessage {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(Crayon.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(focus.storageBlocked ? "重试读取" : "重试本地保存") { focus.retrySave() }
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 10).background(Crayon.paper)
            .overlay(alignment: .top) { Rectangle().fill(Crayon.ink.opacity(0.25)).frame(height: 1) }
            .alert("放弃这一轮计时？", isPresented: $abandon) {
                Button("取消", role: .cancel) {}
                Button("放弃计时", role: .destructive) { focus.abandon() }
            } message: { Text("未完成的一轮不计入统计，历史记录保留。") }
    }
    @ViewBuilder private var current: some View {
        if let run = focus.archive.run {
            HStack(spacing: 10) {
                Image(systemName: run.kind == .work ? "timer" : "cup.and.saucer.fill").foregroundStyle(Crayon.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.activeTitle).font(.system(size: 13, weight: .bold)).lineLimit(1).frame(maxWidth: 200, alignment: .leading)
                    Text(run.kind == .work ? "专注 · \(run.running ? "计时中" : (run.remaining == 0 ? "已结束" : "已暂停"))" : "短休息").font(.caption).foregroundStyle(Crayon.muted)
                }
                Text(focus.displayTime).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit().fixedSize()
                if run.remaining > 0 {
                    Button(run.running ? "暂停" : "继续") { if run.running { focus.pause() } else { Task { await focus.resume() } } }
                    Button("重置") { focus.reset() }
                }
                Button(run.remaining == 0 ? "收起" : "放弃") { if run.remaining == 0 { focus.abandon() } else { abandon = true } }
            }
        } else { Label("选一条任务，开始小小的专注", systemImage: "timer").font(.system(size: 13, weight: .semibold)) }
    }
    private var statistics: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("今日 \(focus.statistics.todayCount) 轮 · \(focus.statistics.todayMinutes) 分钟")
            Text("本周 \(focus.statistics.weekCount) 轮 · \(focus.statistics.weekMinutes) 分钟")
        }.font(.caption).foregroundStyle(Crayon.muted).fixedSize()
    }
    private var controls: some View {
        HStack(spacing: 10) {
            Toggle("提示音", isOn: Binding(get: { focus.archive.soundEnabled }, set: { enabled in Task { await focus.setSound(enabled) } })).toggleStyle(.checkbox)
            Button("启用通知") { Task { await focus.requestNotifications() } }.help(focus.notificationStatus)
        }.font(.caption).fixedSize()
    }
}
