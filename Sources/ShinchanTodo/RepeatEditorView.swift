import SwiftUI
import TodoCore

/// All edits belong to the existing task draft and require Save Task.
struct RepeatEditorView: View {
    @Binding var draft: TaskDraft
    let task: TodoTask?
    @State private var custom: Bool
    @State private var intervalText: String
    @State private var countText: String
    @State private var errors: [String: String] = [:]

    init(draft: Binding<TaskDraft>, task: TodoTask?) {
        _draft = draft; self.task = task
        _custom = State(initialValue: RepeatPreset.matching(draft.wrappedValue.repeatRule) == .custom)
        _intervalText = State(initialValue: String(draft.wrappedValue.repeatRule.schedule?.interval ?? 1))
        if case .after(let count) = draft.wrappedValue.repeatRule.schedule?.end { _countText = State(initialValue: String(count)) }
        else { _countText = State(initialValue: "12") }
    }
    private var editable: Bool { task?.canEditRepeat ?? draft.repeatRule.isEditable }
    private var schedule: RepeatSchedule { draft.repeatRule.schedule ?? RepeatSchedule(frequency: .daily) }
    private var preset: Binding<RepeatPreset> {
        Binding(get: { custom ? .custom : RepeatPreset.matching(draft.repeatRule) }, set: { value in
            if value == .custom {
                custom = true
                if draft.repeatRule == .none { draft.repeatRule = .daily }
            } else {
                custom = false; draft.repeatRule = value.rule(end: schedule.end)
            }
            resetInput()
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重复规则").font(.system(size: 13, weight: .bold))
            if !draft.repeatRule.isEditable {
                Label(draft.repeatRule.title, systemImage: "repeat")
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("这条规则含当前编辑器未覆盖的设置，已保留原样。请在苹果提醒事项中修改重复；标题、备注和优先级仍可编辑。")
                    .font(.caption).foregroundStyle(Crayon.muted)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("重复", selection: preset) { ForEach(RepeatPreset.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    if custom, draft.repeatRule != .none { customFields }
                    if draft.repeatRule != .none { endFields }
                }.disabled(!editable)
                if let error = draft.repeatInputError {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(Crayon.red)
                } else if let value = draft.repeatRule.schedule, (try? value.validated(start: draft.dueDate)) == nil {
                    Text("请核对日期选择及结束条件；结束日期不能早于首次任务时间。")
                        .foregroundStyle(Crayon.red)
                }
                if draft.repeatRule != .none {
                    Label(draft.repeatRule.title, systemImage: "repeat").fixedSize(horizontal: false, vertical: true)
                    Text("\(editable ? "保存任务后生效。完成当前一次后由苹果提供下一次任务。" : "已完成任务的重复规则只读，请先恢复任务。")")
                        .font(.caption).foregroundStyle(Crayon.muted)
                    if schedule.frequency == .monthly && schedule.monthDays.contains(where: { $0 >= 29 }) {
                        Text("没有所选日期的月份由苹果处理，不自动改成月末；需要月末请选择“最后一天”。")
                            .font(.caption).foregroundStyle(Crayon.muted)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Crayon.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Crayon.ink.opacity(0.25)).allowsHitTesting(false))
        .onChange(of: task?.repeatRule) { _, _ in
            custom = RepeatPreset.matching(draft.repeatRule) == .custom; resetInput()
        }
    }
    private var customFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("频率", selection: Binding(get: { schedule.frequency }, set: { frequency in
                var value = RepeatSchedule(frequency: frequency, interval: schedule.interval, end: schedule.end)
                if frequency == .weekly { value.weekdays = [Calendar.current.component(.weekday, from: draft.dueDate ?? Date())] }
                draft.repeatRule = .scheduled(value)
            })) { ForEach(RepeatFrequency.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            HStack {
                Text("每隔")
                TextField("1", text: Binding(get: { intervalText }, set: { text in
                    intervalText = text
                    if let number = integer(text, range: 1...999) { change { $0.interval = number }; errors.removeValue(forKey: "interval") }
                    else { errors["interval"] = "重复间隔请输入 1～999 的整数。" }
                    updateError()
                })).textFieldStyle(.roundedBorder).frame(width: 70).accessibilityLabel("重复间隔")
                Text(schedule.frequency.unit)
            }
            if schedule.frequency == .weekly { weekdayFields }
            if schedule.frequency == .monthly { monthlyFields }
            if schedule.frequency == .yearly { Text("按首次任务的月、日重复；闰日规则由苹果处理。").foregroundStyle(Crayon.muted) }
        }
    }
    private var weekdayFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择星期（可多选）")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Toggle(RepeatSchedule.weekdayTitle(day), isOn: Binding(get: { schedule.weekdays.contains(day) }, set: { on in
                        change { value in
                            value.weekdays.removeAll { $0 == day }
                            if on { value.weekdays.append(day); value.weekdays.sort() }
                        }
                    })).toggleStyle(.checkbox)
                }
            }
            if schedule.weekdays.isEmpty { Text("未选星期：按首次任务所在的星期几重复。").foregroundStyle(Crayon.muted) }
        }
    }
    private var monthlyFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("月内规则", selection: Binding(get: { schedule.ordinal != nil ? 2 : (schedule.monthDays.isEmpty ? 0 : 1) }, set: { mode in
                change { value in
                    value.weekdays = []; value.monthDays = []; value.ordinal = nil
                    if mode == 1 { value.monthDays = [Calendar.current.component(.day, from: draft.dueDate ?? Date())] }
                    if mode == 2 { value.ordinal = 1; value.weekdays = [Calendar.current.component(.weekday, from: draft.dueDate ?? Date())] }
                }
            })) {
                Text("按首次任务的日期").tag(0)
                Text("指定日期（可多选）").tag(1)
                Text("第几个星期几").tag(2)
            }.pickerStyle(.menu)
            if schedule.ordinal != nil {
                Picker("次序", selection: Binding(get: { schedule.ordinal ?? 1 }, set: { number in change { $0.ordinal = number } })) {
                    ForEach(1...5, id: \.self) { Text("第 \($0) 个").tag($0) }
                    Text("最后一个").tag(-1)
                }.pickerStyle(.menu)
                Picker("星期", selection: Binding(get: { schedule.weekdays.first ?? 2 }, set: { day in change { $0.weekdays = [day] } })) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(RepeatSchedule.weekdayTitle($0)).tag($0) }
                }.pickerStyle(.menu)
            } else if !schedule.monthDays.isEmpty {
                Text("可多选，至少保留一个日期；也可选择月末。").foregroundStyle(Crayon.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                    ForEach(Array(1...31) + [-1], id: \.self) { day in
                        Button {
                            // Keep at least one selected date; no accidental fallback to anchor-date mode.
                            change { value in
                                if value.monthDays.contains(day) { if value.monthDays.count > 1 { value.monthDays.removeAll { $0 == day } } }
                                else { value.monthDays.append(day); value.monthDays.sort() }
                            }
                        } label: {
                            Text(day == -1 ? "月末" : String(day)).frame(maxWidth: .infinity, minHeight: 26).contentShape(Rectangle())
                        }.buttonStyle(.bordered).tint(schedule.monthDays.contains(day) ? Crayon.red : Crayon.muted)
                            .accessibilityLabel(day == -1 ? "最后一天" : "每月 \(day) 日")
                            .accessibilityValue(schedule.monthDays.contains(day) ? "已选择" : "未选择")
                    }
                }
            }
        }
    }
    private var endFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("结束重复", selection: Binding(get: {
                switch schedule.end { case .never: 0; case .onDate: 1; case .after: 2 }
            }, set: { mode in
                errors.removeValue(forKey: "count")
                change { value in
                    switch mode {
                    case 1: value.end = .onDate(RepeatSchedule.endOfDay(max(draft.dueDate ?? Date(), Date())))
                    case 2: countText = "12"; value.end = .after(12)
                    default: value.end = .never
                    }
                }; updateError()
            })) {
                Text("永不").tag(0); Text("指定日期").tag(1); Text("指定次数").tag(2)
            }.pickerStyle(.menu)
            if case .onDate(let date) = schedule.end {
                DatePicker("最后日期", selection: Binding(get: { date }, set: { day in change { $0.end = .onDate(RepeatSchedule.endOfDay(day)) } }), displayedComponents: .date)
            }
            if case .after = schedule.end {
                HStack {
                    Text("共重复")
                    TextField("12", text: Binding(get: { countText }, set: { text in
                        countText = text
                        if let number = integer(text, range: 1...9999) { change { $0.end = .after(number) }; errors.removeValue(forKey: "count") }
                        else { errors["count"] = "重复次数请输入 1～9999 的整数。" }
                        updateError()
                    })).textFieldStyle(.roundedBorder).frame(width: 70).accessibilityLabel("重复总次数")
                    Text("次（含首次）")
                }
            }
        }
    }
    private func change(_ transform: (inout RepeatSchedule) -> Void) {
        var value = schedule; transform(&value); draft.repeatRule = .scheduled(value)
    }
    private func integer(_ text: String, range: ClosedRange<Int>) -> Int? {
        FocusDurationInput.minutes(from: text, in: range)
    }
    private func updateError() { draft.repeatInputError = errors.keys.sorted().compactMap { errors[$0] }.first }
    private func resetInput() {
        intervalText = String(schedule.interval)
        if case .after(let count) = schedule.end { countText = String(count) }
        errors = [:]; draft.repeatInputError = nil
    }
}
