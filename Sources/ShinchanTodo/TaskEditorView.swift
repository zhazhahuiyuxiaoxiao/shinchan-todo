import SwiftUI
import TodoCore

struct TaskEditorView: View {
    @ObservedObject var model: TodoController
    @ObservedObject var focus: FocusController
    let onCancel: () -> Void
    let onDelete: (TodoTask) -> Void
    let onReload: (TodoTask) -> Void
    let onSave: () -> Void
    let onLearningDirty: (Bool) -> Void
    @FocusState private var titleFocused: Bool
    var body: some View {
        if model.hasEditor {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(model.editingTask == nil ? "写下一件小事" : "任务详情").font(.system(size: 21, weight: .black, design: .rounded))
                        Spacer(); if model.isDirty { Text("未保存").font(.system(size: 11, weight: .bold)).foregroundStyle(Crayon.red) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("标题").font(.system(size: 13, weight: .bold))
                        TextField("想做什么？", text: $model.draft.title, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).focused($titleFocused)
                    }
                    if let task = model.editingTask { TaskLearningCard(focus: focus, task: task, onDirty: onLearningDirty).id(model.editorGeneration) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注").font(.system(size: 13, weight: .bold))
                        TextEditor(text: $model.draft.notes).font(.system(size: 14)).scrollContentBackground(.hidden).padding(7).frame(minHeight: 150)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Crayon.ink.opacity(0.4))).accessibilityLabel("任务备注")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("设置截止日期", isOn: Binding(get: { model.draft.dueDate != nil }, set: { model.draft.dueDate = $0 ? Calendar.current.startOfDay(for: Date()) : nil }))
                            .disabled(model.editingTask?.advancedDate == true)
                        if model.draft.dueDate != nil {
                            DatePicker("截止日期", selection: Binding(get: { model.draft.dueDate ?? Date() }, set: { model.draft.dueDate = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date)
                                .disabled(model.editingTask?.advancedDate == true)
                        }
                        Text(model.editingTask?.advancedDate == true ? "含具体时间或重复设置，日期请在苹果提醒事项中修改。其他字段仍可编辑。" : "只记录日期，暂不配置提醒通知。")
                    }.font(.system(size: 12)).foregroundStyle(Crayon.muted)
                    Picker("优先级", selection: $model.draft.priority) { ForEach(TaskPriority.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    RepeatEditorView(draft: $model.draft, task: model.editingTask)
                        .id(model.editorGeneration)
                    HStack(spacing: 12) {
                        Button("保存任务", action: onSave).buttonStyle(CrayonButton(fill: Crayon.red, foreground: .white))
                            .keyboardShortcut("s", modifiers: .command).disabled(model.busy)
                        Button("取消", action: onCancel).buttonStyle(CrayonButton(fill: Crayon.paper)).disabled(model.busy)
                    }
                    if let task = model.editingTask { FocusCard(focus: focus, task: task).id(FocusKey(task: task)) }
                    else { Text("先保存任务，就可以为它设置专注计时。").font(.caption).foregroundStyle(Crayon.muted) }
                    if let task = model.editingTask {
                        Divider()
                        HStack {
                            Button("载入最新任务") { onReload(task) }.buttonStyle(.link).disabled(model.busy)
                            Spacer()
                            Button("删除任务", role: .destructive) { onDelete(task) }.buttonStyle(.link).disabled(model.busy)
                        }.font(.system(size: 12))
                    }
                }.padding(22)
            }.background(Crayon.cream).onAppear { titleFocused = model.editingTask == nil }
                .onChange(of: model.editingTask?.id) { _, id in titleFocused = id == nil }
        } else {
            VStack(spacing: 18) {
                ShinchanDecoration(width: 230)
                Text("小小的任务，也值得认真完成。").font(.system(size: 16, weight: .bold)).multilineTextAlignment(.center)
                Text("选一条任务查看详情，\n或新建一件今天想做的小事。").font(.system(size: 13)).foregroundStyle(Crayon.muted).multilineTextAlignment(.center)
            }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity).background(Crayon.cream)
        }
    }
}
