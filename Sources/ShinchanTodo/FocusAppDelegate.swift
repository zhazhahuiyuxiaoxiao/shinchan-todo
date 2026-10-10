import AppKit
import TodoCore

@MainActor final class FocusAppDelegate: NSObject, NSApplicationDelegate {
    var focus: FocusController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let focus else { return .terminateNow }
        focus.pause()
        if focus.hasUnsavedArchive {
            let alert = NSAlert()
            alert.messageText = "专注记录还没有保存成功"
            alert.informativeText = "退出会丢失尚未保存的专注记录或设置。可以取消退出，重试本地保存。"
            alert.addButton(withTitle: "取消退出")
            alert.addButton(withTitle: "仍然退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        // 先保存暂停状态，等在途通知提交结束并取消，再完成正常退出。
        Task { await focus.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
