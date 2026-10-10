import Foundation
import Combine
import AppKit
import TodoCore

/// 由 App 持有，计时与生命周期不依赖某个窗口是否仍显示。
@MainActor public final class FocusRuntime {
    private var subscriptions: Set<AnyCancellable> = []
    public init(focus: FocusController) {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { _ in focus.tick() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { _ in focus.pause() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in focus.pause() }.store(in: &subscriptions)
    }
}
