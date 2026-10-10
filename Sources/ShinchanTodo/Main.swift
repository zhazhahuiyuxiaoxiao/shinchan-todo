import SwiftUI
import EventKit
import TodoCore
import TodoSystem

@main struct ShinchanTodoApp: App {
    @NSApplicationDelegateAdaptor(FocusAppDelegate.self) private var appDelegate
    @StateObject private var model: TodoController
    @StateObject private var focus: FocusController
    private let focusRuntime: FocusRuntime
    private let demo: Bool
    init() {
        demo = CommandLine.arguments.contains("--demo")
        let todo: TodoController
        if demo {
            todo = TodoController(backend: DemoBackend(), calendarID: DemoBackend.listID)
        } else {
            let binding = UserDefaults.standard.string(forKey: "dedicatedReminderCalendarID")
            todo = TodoController(backend: EventKitBackend(), calendarID: binding.flatMap { $0.isEmpty ? nil : $0 }, onBind: { id in
                if id.isEmpty { UserDefaults.standard.removeObject(forKey: "dedicatedReminderCalendarID") }
                else { UserDefaults.standard.set(id, forKey: "dedicatedReminderCalendarID") }
            })
        }
        let timer = FocusController(todo: todo, store: demo ? MemoryFocusStore() : FileFocusStore.applicationStore(), notifier: demo ? DemoFocusNotifier() : SystemFocusNotifier())
        _model = StateObject(wrappedValue: todo); _focus = StateObject(wrappedValue: timer)
        focusRuntime = FocusRuntime(focus: timer)
    }
    var body: some Scene {
        WindowGroup("小新待办") {
            RootView(model: model, demo: demo, focus: focus)
                .frame(minWidth: 940, minHeight: 660).preferredColorScheme(.light)
                .task {
                    appDelegate.focus = focus
                    if model.calendarID != nil { if demo { await model.refresh() } else { await model.connect() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                    if !demo, model.calendarID != nil { Task { await model.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshClock()
                    if model.calendarID != nil { Task { await model.refresh() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    model.refreshClock()
                    if model.calendarID != nil { Task { await model.refresh() } }
                }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in model.refreshClock() }
        }
        .defaultSize(width: 1180, height: 800).windowStyle(.titleBar).windowResizability(.contentMinSize)
    }
}
