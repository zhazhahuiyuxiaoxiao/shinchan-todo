import SwiftUI
import TodoCore

struct SidebarView: View {
    @ObservedObject var model: TodoController
    let demo: Bool
    let onReset: () -> Void
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            Text("我的小清单").font(.system(size: 13, weight: .bold)).foregroundStyle(Crayon.muted)
            ForEach(TaskView.allCases) { view in
                Button { model.query.view = view; model.query.status = .all } label: {
                    HStack(spacing: 12) { Image(systemName: view.icon).frame(width: 20); Text(view.title); Spacer() }
                        .font(.system(size: 15, weight: .bold)).padding(12)
                        .background(model.query.view == view ? Crayon.yellow : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.query.view == view ? Crayon.ink : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(model.query.view == view ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("一点点，也算进步").font(.system(size: 14, weight: .bold))
                stat("全部", value: model.statistics.total); stat("未完成", value: model.statistics.pending)
                Divider()
                HStack { Text("完成比例"); Spacer(); Text(model.statistics.completionRatio, format: .percent.precision(.fractionLength(0))).bold() }.font(.system(size: 13))
                ProgressView(value: model.statistics.completionRatio).tint(Crayon.red)
                Text("统计整个专用清单").font(.system(size: 11)).foregroundStyle(Crayon.muted)
            }.paperPanel()
            Spacer(minLength: 10)
            Label(demo ? "纯内存演示" : "苹果提醒事项", systemImage: demo ? "sparkles" : "checklist")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Crayon.muted)
            if !demo { Button("重新设置新清单", action: onReset).buttonStyle(.link).font(.system(size: 12)).disabled(model.busy) }
        }.padding(18)
        }.background(Crayon.cream)
    }
    private func stat(_ title: String, value: Int) -> some View {
        HStack { Text(title).font(.system(size: 13)); Spacer(); Text("\(value)").font(.system(size: 21, weight: .black, design: .rounded)) }
    }
}
struct TaskListView: View {
    @ObservedObject var model: TodoController
    let onSelect: (TodoTask) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(model.query.view.title).font(.system(size: 23, weight: .black, design: .rounded)); Spacer(); if model.loading { ProgressView().controlSize(.small) } }
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(Crayon.muted); TextField("搜索标题和备注", text: $model.query.search).textFieldStyle(.plain) }
                .padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Crayon.ink.opacity(0.35)))
            HStack(spacing: 8) {
                Picker("状态", selection: $model.query.status) { ForEach(TaskStatus.allCases) { Text($0.title).tag($0) } }.labelsHidden().help("按完成状态筛选")
                Picker("优先级", selection: $model.query.priority) {
                    Text("全部优先级").tag(nil as TaskPriority?)
                    ForEach(TaskPriority.allCases) { Text("\($0.title)优先级").tag(Optional($0)) }
                }.labelsHidden().help("按优先级筛选")
            }.pickerStyle(.menu)
            Text("\(model.visibleTasks.count) 条符合条件的任务").font(.system(size: 12)).foregroundStyle(Crayon.muted)
            if model.visibleTasks.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "leaf").font(.system(size: 36)).foregroundStyle(Crayon.red)
                    Text(model.tasks.isEmpty ? "从一件小事开始吧" : "没有符合条件的任务").font(.headline)
                    Text(model.tasks.isEmpty ? "点击右上角新建任务。" : "调整搜索、状态或优先级筛选。").font(.system(size: 13)).foregroundStyle(Crayon.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { LazyVStack(spacing: 12) { ForEach(model.visibleTasks) { task in row(task) } }.padding(.vertical, 4).padding(.horizontal, 2) }
            }
        }.padding(20).background(Crayon.paper)
    }
    private func row(_ task: TodoTask) -> some View {
        ZStack(alignment: .topLeading) {
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title).font(.system(size: 15, weight: .bold)).strikethrough(task.completed).lineLimit(3).multilineTextAlignment(.leading)
                    if !FocusNotes.editableNotes(task.notes).isEmpty { Text(FocusNotes.editableNotes(task.notes)).font(.system(size: 12)).foregroundStyle(Crayon.muted).lineLimit(2).multilineTextAlignment(.leading) }
                    HStack(spacing: 8) {
                        if let due = task.dueDate { Label(due.formatted(.dateTime.month().day()), systemImage: "calendar").font(.system(size: 11)) }
                        Text(task.priority == .none ? "无优先级" : "\(task.priority.title)优先级").font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3).background(task.priority == .high ? Crayon.yellow : Crayon.sky, in: Capsule())
                    }
                    if task.repeatRule != .none {
                        Label(task.repeatRule == .daily ? "每天重复" : "其他重复规则", systemImage: "repeat")
                            .font(.system(size: 11)).foregroundStyle(Crayon.muted)
                    }
                }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.vertical, 3).padding(.leading, 44).padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .contentShape(RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).accessibilityLabel("编辑任务：\(task.title)").disabled(model.busy)
            // 完成按钮是独立兄弟控件，不嵌套在编辑按钮中，圆圈以外均打开详情。
            Button { Task { await model.toggle(task) } } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 23))
                    .foregroundStyle(task.completed ? Crayon.red : Crayon.ink).frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(task.completed ? "恢复" : "完成")任务：\(task.title)")
                .disabled(model.busy || (model.isDirty && model.editingTask?.id == task.id)).padding(12)
        }.overlay(RoundedRectangle(cornerRadius: 13).stroke(model.editingTask?.id == task.id ? Crayon.red : Crayon.ink.opacity(0.55), lineWidth: model.editingTask?.id == task.id ? 2 : 1).allowsHitTesting(false))
    }
}
