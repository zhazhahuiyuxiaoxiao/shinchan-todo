import SwiftUI
import TodoCore

struct LearningProgressView: View {
    @ObservedObject var focus: FocusController
    let task: TodoTask
    var decorativeProgress = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title = focus.learningTitle(for: task) {
                Label(title, systemImage: "map").font(.system(size: 12, weight: .semibold))
                    .lineLimit(2).help(title)
            }
            let progress = focus.dailyProgress(for: task)
            if let goal = progress.goalMinutes {
                Text(progress.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(progress.reachedGoal ? Crayon.red : Crayon.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: min(1, Double(progress.completedMinutes) / Double(goal)))
                    .tint(Crayon.red).accessibilityLabel("今日专注时长进度")
                    .accessibilityValue("目标 \(goal) 分钟，完整专注 \(progress.completedMinutes) 分钟")
                    .accessibilityHidden(decorativeProgress)
            }
        }
    }
}

struct TaskLearningCard: View {
    @ObservedObject var focus: FocusController
    let task: TodoTask
    let onDirty: (Bool) -> Void
    @State private var goalEnabled: Bool
    @State private var goalText: String
    @State private var routeID: UUID?
    @State private var stageID: UUID?
    @State private var baselineGoal: Int?
    @State private var baselineContext: LearningContext?
    @State private var message: String?
    init(focus: FocusController, task: TodoTask, onDirty: @escaping (Bool) -> Void) {
        self.focus = focus; self.task = task; self.onDirty = onDirty
        let goal = focus.dailyGoal(for: task); let context = focus.learningContext(for: task)
        _goalEnabled = State(initialValue: goal != nil); _goalText = State(initialValue: goal.map(String.init) ?? "120")
        _routeID = State(initialValue: context?.routeID); _stageID = State(initialValue: context?.stageID)
        _baselineGoal = State(initialValue: goal); _baselineContext = State(initialValue: context)
    }
    private var selectedContext: LearningContext? {
        guard let routeID, let stageID else { return nil }
        return LearningContext(routeID: routeID, stageID: stageID)
    }
    private var isDirty: Bool {
        goalEnabled != (baselineGoal != nil) || (goalEnabled && goalText != baselineGoal.map(String.init)) ||
        routeID != baselineContext?.routeID || stageID != baselineContext?.stageID
    }
    private var locked: Bool { focus.archive.run?.key == FocusKey(task: task) && (focus.archive.run?.remaining ?? 0) > 0 }
    private var selectedRoute: LearningRoute? { focus.archive.routes.first { $0.id == routeID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("学习阶段与今日目标", systemImage: "map").font(.system(size: 14, weight: .bold))
                Spacer()
                if isDirty { Text("未保存").font(.caption).foregroundStyle(Crayon.red) }
            }
            LearningProgressView(focus: focus, task: task)
            if let next = focus.suggestedStage(for: task) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("当前阶段已打卡，下一步：\(next.title)").font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button("选择下一阶段") { stageID = next.id; message = "已选择下一阶段，请保存学习设置。" }
                        .disabled(locked || task.completed || focus.storageBlocked)
                }.padding(10).background(Crayon.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 10) {
                Picker("学习路线", selection: $routeID) {
                    Text("不关联路线").tag(nil as UUID?)
                    if let routeID, selectedRoute == nil { Text("原关联在本机不可用").tag(Optional(routeID)) }
                    ForEach(focus.archive.routes) { route in Text(route.title).tag(Optional(route.id)) }
                }.pickerStyle(.menu)
                if let route = selectedRoute {
                    Picker("关联阶段", selection: $stageID) {
                        Text("请选择阶段").tag(nil as UUID?)
                        ForEach(route.stages) { stage in Text(stage.title + (stage.completedAt == nil ? "" : "（已打卡）")).tag(Optional(stage.id)) }
                    }.pickerStyle(.menu)
                    if route.stages.isEmpty { Text("请先在学习路线页添加阶段。").font(.caption).foregroundStyle(Crayon.muted) }
                }
                Toggle("设置每日学习目标", isOn: $goalEnabled)
                if goalEnabled {
                    HStack {
                        Text("每日目标").font(.system(size: 13, weight: .semibold))
                        TextField("1～1440", text: $goalText).textFieldStyle(.roundedBorder).frame(width: 78)
                            .accessibilityLabel("每日学习目标分钟数").onSubmit(save)
                        Text("分钟").font(.caption)
                    }
                }
                Button("保存学习设置", action: save).buttonStyle(CrayonButton(fill: Crayon.yellow)).disabled(!isDirty)
            }.disabled(locked || task.completed || focus.storageBlocked || focus.todo.busy)
            if let message { Text(message).font(.caption).foregroundStyle(Crayon.red).fixedSize(horizontal: false, vertical: true) }
            Text(locked ? "本轮结束或放弃后可调整学习设置。" : "每日目标每天重新计算；仅完整结束的番茄轮次计入，达标后仍可继续。")
                .font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true)
        }.paperPanel()
        .onChange(of: routeID) { _, value in
            if value != baselineContext?.routeID { stageID = nil }
            else if stageID == nil { stageID = baselineContext?.stageID }
        }
        .onChange(of: isDirty) { _, value in onDirty(value) }
        .onChange(of: focus.archive.preferences) { _, _ in if !isDirty { reload() } }
        .onChange(of: task.notes) { _, _ in if !isDirty { reload() } }
        .onDisappear { onDirty(false) }
    }
    private func reload() {
        baselineGoal = focus.dailyGoal(for: task); baselineContext = focus.learningContext(for: task)
        goalEnabled = baselineGoal != nil; goalText = baselineGoal.map(String.init) ?? "120"
        routeID = baselineContext?.routeID; stageID = baselineContext?.stageID
    }
    private func save() {
        guard !locked, !task.completed else { return }
        let goal = goalEnabled ? FocusDurationInput.minutes(from: goalText, in: 1...1440) : nil
        if goalEnabled && goal == nil { message = "请输入 1～1440 的整数分钟，原目标未改变。"; return }
        if routeID != nil && selectedContext == nil { message = "请选择一个学习阶段。"; return }
        let current = focus.todo.editingTask.flatMap { FocusKey(task: $0) == FocusKey(task: task) ? $0 : nil } ?? task
        do {
            try focus.setLearning(dailyGoal: goal, context: selectedContext, for: current)
            reload(); onDirty(false); message = nil
        } catch { message = error.localizedDescription }
    }
}

struct LearningRoutesView: View {
    @ObservedObject var focus: FocusController
    let onTask: (TodoTask) -> Void
    @State private var selectedID: UUID?
    @State private var editor: NameEdit?
    @State private var error: String?
    private struct NameEdit: Identifiable {
        enum Action { case newRoute, route(UUID), newStage(UUID), stage(UUID, UUID) }
        let id = UUID()
        let heading: String
        let text: String
        let action: Action
    }
    private var selected: LearningRoute? { focus.archive.routes.first { $0.id == selectedID } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("学习路线").font(.system(size: 23, weight: .black, design: .rounded))
                    Spacer()
                    Button { editor = NameEdit(heading: "新建学习路线", text: "", action: .newRoute) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建学习路线").disabled(focus.storageBlocked)
                }
                Text("让每一步，都看得见。完成阶段后手动打卡。").font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true)
                if focus.archive.routes.isEmpty {
                    Text("还没有学习路线\n先新建一条，再添加阶段。原备注会保留。").font(.system(size: 14)).foregroundStyle(Crayon.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(focus.archive.routes) { route in
                                Button { selectedID = route.id } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(route.title).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.leading)
                                        Text("已完成 \(route.completedCount) / \(route.stages.count) 个阶段").font(.caption)
                                        ProgressView(value: route.progress).tint(Crayon.red).accessibilityHidden(true)
                                        if !route.stages.isEmpty && route.completedCount == route.stages.count { Label("路线阶段全部打卡", systemImage: "checkmark.seal").font(.caption) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                        .background(selectedID == route.id ? Crayon.yellow.opacity(0.4) : .white, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedID == route.id ? Crayon.red : Crayon.ink.opacity(0.4)))
                                        .contentShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("\(route.title)，已完成 \(route.completedCount) / \(route.stages.count) 个阶段").accessibilityAddTraits(selectedID == route.id ? .isSelected : [])
                            }
                        }.padding(2)
                    }
                }
            }.padding(20).frame(minWidth: 280, idealWidth: 330, maxWidth: 480).background(Crayon.paper)
            ScrollView {
                if let route = selected {
                    routeDetail(route)
                } else {
                    VStack(spacing: 18) {
                        ShinchanDecoration(width: 210)
                        Text("选一条路线，看看走到哪一步。").font(.headline).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(30)
                }
            }.frame(minWidth: 320).background(Crayon.cream)
        }
        .sheet(item: $editor) { item in
            LearningNameEditor(heading: item.heading, initialText: item.text) { title in
                switch item.action {
                case .newRoute: selectedID = try focus.addRoute(title: title, id: item.id)
                case .route(let id): try focus.renameRoute(id, title: title)
                case .newStage(let id): _ = try focus.addStage(title: title, to: id, id: item.id)
                case .stage(let route, let stage): try focus.renameStage(stage, in: route, title: title)
                }
                editor = nil
            } onCancel: { editor = nil }
        }
        .onAppear { if selectedID == nil { selectedID = focus.archive.routes.first?.id } }
    }
    private func routeDetail(_ route: LearningRoute) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(route.title).font(.system(size: 23, weight: .black, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("已完成 \(route.completedCount) / \(route.stages.count) 个阶段").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("改名") { editor = NameEdit(heading: "路线改名", text: route.title, action: .route(route.id)) }
            }
            ProgressView(value: route.progress).tint(Crayon.red)
            Button("添加阶段") { editor = NameEdit(heading: "添加学习阶段", text: "", action: .newStage(route.id)) }
                .buttonStyle(CrayonButton(fill: Crayon.yellow))
            if route.stages.isEmpty { Text("按你想学习的顺序添加阶段，例如：基础 → 练习 → 项目。") }
            ForEach(Array(route.stages.enumerated()), id: \.element.id) { index, stage in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Button { perform { try focus.toggleStage(stage.id, in: route.id) } } label: {
                            Image(systemName: stage.completedAt == nil ? "circle" : "checkmark.circle.fill")
                                .font(.system(size: 25)).foregroundStyle(stage.completedAt == nil ? Crayon.ink : Crayon.red)
                                .frame(width: 34, height: 34).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(stage.completedAt == nil ? "打卡完成" : "恢复")阶段：\(stage.title)")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(index + 1). \(stage.title)").font(.system(size: 15, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                            if let date = stage.completedAt {
                                Text("已打卡 · \(date.formatted(.dateTime.year().month().day().hour().minute()))").font(.caption).foregroundStyle(Crayon.muted)
                            } else { Text("待学习 · 完成后由你确认打卡").font(.caption).foregroundStyle(Crayon.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 14) {
                        Button("改名") { editor = NameEdit(heading: "阶段改名", text: stage.title, action: .stage(route.id, stage.id)) }
                        Spacer()
                        Button { perform { try focus.moveStage(stage.id, in: route.id, offset: -1) } } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).accessibilityLabel("上移阶段：\(stage.title)")
                        Button { perform { try focus.moveStage(stage.id, in: route.id, offset: 1) } } label: { Image(systemName: "arrow.down") }
                            .disabled(index == route.stages.count - 1).accessibilityLabel("下移阶段：\(stage.title)")
                    }.font(.caption)
                }.paperPanel()
            }
            if let error { Text(error).font(.caption).foregroundStyle(Crayon.red).fixedSize(horizontal: false, vertical: true) }
            let tasks = focus.todo.tasks.filter { focus.learningContext(for: $0)?.routeID == route.id }
            if !tasks.isEmpty {
                Divider()
                Text("关联的日常任务").font(.headline)
                ForEach(tasks) { task in
                    Button { onTask(task) } label: {
                        Label(task.title, systemImage: task.completed ? "checkmark.circle" : "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                    }
                }
            }
            Text("阶段打卡只改变学习路线进度；每日任务和时长目标独立管理。").font(.caption).foregroundStyle(Crayon.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(22).disabled(focus.storageBlocked)
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct LearningNameEditor: View {
    let heading: String
    @State private var text: String
    @State private var error: String?
    @FocusState private var focused: Bool
    let onSave: (String) throws -> Void
    let onCancel: () -> Void
    init(heading: String, initialText: String, onSave: @escaping (String) throws -> Void, onCancel: @escaping () -> Void) {
        self.heading = heading; _text = State(initialValue: initialText); self.onSave = onSave; self.onCancel = onCancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(heading).font(.title2.bold())
            TextField("名称", text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                .accessibilityLabel(heading + "名称").focused($focused).onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(Crayon.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: save).buttonStyle(CrayonButton(fill: Crayon.yellow)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420).background(Crayon.cream).onAppear { focused = true }
    }
    private func save() { do { try onSave(text) } catch { self.error = error.localizedDescription } }
}
