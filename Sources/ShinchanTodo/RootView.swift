import SwiftUI
import TodoCore
import TodoSystem

struct RootView: View {
    @ObservedObject var model: TodoController
    let demo: Bool
    @ObservedObject var focus: FocusController
    @State private var deleteTarget: TodoTask?
    @State private var pendingAction: (() -> Void)?
    @State private var showDiscard = false
    @State private var showReset = false
    @State private var showDemo = false
    @State private var showSidebar = true
    @State private var showLearningRoutes = false
    @State private var learningDirty = false
    @State private var discardMessage = "任务或学习设置尚未保存。继续会丢弃这些未保存的内容。"
    var body: some View {
        Group {
            if showDemo { DemoPreviewView(onClose: { showDemo = false }) }
            else { workspace }
        }
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            header
            if demo {
                Text("演示模式 · 仅保存在内存，不连接苹果提醒事项；可体验重复设置，不生成下一次任务")
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(7).background(Crayon.sky)
            }
            feedback
            if model.phase == .ready {
                HSplitView {
                    if showSidebar {
                        SidebarView(model: model, demo: demo, onReset: { showReset = true }, learningSelected: showLearningRoutes, onTaskView: { view in
                            protectDraft { showLearningRoutes = false; model.query.view = view; model.query.status = .all }
                        }, onLearning: { protectDraft { showLearningRoutes = true; model.closeEditor(); learningDirty = false } })
                            .frame(minWidth: 190, idealWidth: 215, maxWidth: 240)
                    }
                    if showLearningRoutes {
                        LearningRoutesView(focus: focus, onTask: { task in
                            protectDraft { showLearningRoutes = false; _ = model.select(task, discardChanges: true) }
                        })
                    } else {
                        TaskListView(model: model, focus: focus, onSelect: { task in protectDraft { _ = model.select(task, discardChanges: true) } })
                            .frame(minWidth: 300, idealWidth: 410, maxWidth: 650)
                        TaskEditorView(model: model, focus: focus, onCancel: { protectDraft { model.closeEditor() } }, onDelete: { deleteTarget = $0 }, onReload: { _ in
                            protectDraft { _ = model.reloadEditor(discardChanges: true) }
                        }, onSave: saveTask, onLearningDirty: { learningDirty = $0 }).frame(minWidth: 300)
                    }
                }
            } else { ConnectionView(model: model, onReset: { showReset = true }) }
            FocusBar(focus: focus)
        }.background(Crayon.cream).foregroundStyle(Crayon.ink)
        .alert("放弃未保存的修改？", isPresented: $showDiscard) {
            Button("继续编辑", role: .cancel) { pendingAction = nil }
            Button("放弃修改", role: .destructive) { let action = pendingAction; pendingAction = nil; action?() }
        } message: { Text(discardMessage) }
        .alert("删除这条任务？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { task in
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除任务", role: .destructive) { Task { await model.delete(task) }; deleteTarget = nil }
        } message: { task in
            Text(demo ? "删除“\(task.title)”仅影响本次演示。" : "“\(task.title)”将从苹果提醒事项中删除，并通过 iCloud 影响其他设备。未保存的修改也会丢弃。")
        }
        .alert("重新设置一个新清单？", isPresented: $showReset) {
            Button("取消", role: .cancel) {}
            Button("重新设置") { protectDraft { model.resetConnection() } }
        } message: { Text("只解除应用绑定，原清单和其中的任务保留。随后需要你明确创建一个新清单。") }
    }
    private func saveTask() {
        if learningDirty {
            discardMessage = "学习设置尚未保存。保存任务会关闭详情并丢弃这些学习修改；任务标题和备注将正常保存。"
            pendingAction = { Task { await model.save() } }; showDiscard = true
        } else { Task { await model.save() } }
    }
    private func protectDraft(_ action: @escaping () -> Void) {
        if model.isDirty || learningDirty {
            discardMessage = "任务或学习设置尚未保存。继续会丢弃这些未保存的内容。"
            pendingAction = action; showDiscard = true }
        else { action() }
    }
    private var header: some View {
        HStack(spacing: 15) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 31)).foregroundStyle(Crayon.red).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("小新待办").font(.system(size: 26, weight: .black, design: .rounded))
                Text("今天也要，慢慢把小事做好。").font(.system(size: 12)).foregroundStyle(Crayon.muted)
            }
            Spacer(); ShinchanDecoration(width: 100)
            if !demo, model.phase != .ready {
                Button("先体验演示") { showDemo = true }
                    .buttonStyle(CrayonButton(fill: Crayon.yellow)).disabled(model.busy)
            }
            if model.phase == .ready {
                Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(CrayonButton(fill: Crayon.paper))
                    .accessibilityLabel(showSidebar ? "隐藏侧栏" : "显示侧栏")
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .buttonStyle(CrayonButton(fill: Crayon.paper)).keyboardShortcut("r", modifiers: .command).disabled(model.busy)
                Button { protectDraft { showLearningRoutes = false; _ = model.beginNew(discardChanges: true) } } label: { Label("新建任务", systemImage: "plus") }
                    .buttonStyle(CrayonButton(fill: Crayon.red, foreground: .white)).keyboardShortcut("n", modifiers: .command).disabled(model.busy)
            }
        }.padding(.horizontal, 24).padding(.vertical, 10).background(Crayon.cream)
            .overlay(alignment: .bottom) { Rectangle().fill(Crayon.ink).frame(height: 1.5) }
    }
    @ViewBuilder private var feedback: some View {
        if let notice = model.notice {
            HStack { Image(systemName: "checkmark.circle"); Text(demo ? "演示数据已更新，未写入真实提醒事项。" : notice); Spacer() }
                .font(.system(size: 12)).padding(10).background(Crayon.sky.opacity(0.65))
        }
        if let error = model.errorMessage {
            HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Spacer() }
                .font(.system(size: 13)).padding(12).background(Crayon.yellow.opacity(0.45))
        }
    }
}

private struct DemoPreviewView: View {
    let onClose: () -> Void
    @StateObject private var model: TodoController
    @StateObject private var focus: FocusController
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let todo = TodoController(backend: DemoBackend(), calendarID: DemoBackend.listID)
        _model = StateObject(wrappedValue: todo)
        _focus = StateObject(wrappedValue: FocusController(todo: todo, store: MemoryFocusStore(), notifier: DemoFocusNotifier()))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("界面体验 · 不需要提醒事项权限").font(.headline)
                Spacer()
                Button("结束演示（不保存）", action: onClose).buttonStyle(CrayonButton(fill: Crayon.paper))
            }.padding(12).background(Crayon.cream).layoutPriority(1)
            RootView(model: model, demo: true, focus: focus)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).preferredColorScheme(.light)
            .task { await model.refresh() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in focus.tick() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in focus.pause() }
            .onDisappear { focus.pause() }
    }
}
