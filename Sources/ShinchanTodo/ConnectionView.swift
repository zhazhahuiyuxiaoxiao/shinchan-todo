import SwiftUI
import TodoCore

struct ConnectionView: View {
    @ObservedObject var model: TodoController
    let onReset: () -> Void
    @State private var accountID = ""
    @State private var confirmedICloud = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.phase == .unavailable ? "连接暂时不可用" : "给小事，找个安心的小屋。").font(.system(size: 30, weight: .black, design: .rounded))
                        Text("Mac 用小新待办，手机用苹果提醒事项。\n任务保存到你新建的专用 iCloud 清单。").font(.system(size: 15)).lineSpacing(5)
                    }
                    Spacer(); ShinchanDecoration(width: 210)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("先说清楚访问范围", systemImage: "hand.raised").font(.headline)
                    Text("苹果要求提醒事项的完整读写权限，不能只授权一个清单。本应用只查询和修改绑定的专用清单，不读取其他清单的任务正文。")
                    Text("删除任务会影响苹果提醒事项及同步设备；应用会再次确认。保存成功仅代表本机写入，手机同步由苹果处理。")
                }.font(.system(size: 14)).lineSpacing(5).paperPanel()
                if model.phase == .chooseAccount {
                    if model.accounts.isEmpty {
                        Text("没有可用的 CalDAV 提醒事项账户。请在系统设置中启用 iCloud 提醒事项，并在苹果提醒事项里建立一个普通清单，再刷新。")
                        Button("重新检查账户") { Task { await model.connect() } }.buttonStyle(CrayonButton()).disabled(model.busy)
                    } else {
                        Text("选择你的 iCloud 账户").font(.headline)
                        Picker("账户", selection: $accountID) {
                            Text("请选择账户").tag("")
                            ForEach(model.accounts) { Text($0.title).tag($0.id) }
                        }.frame(maxWidth: 360)
                            .onChange(of: accountID) { _, _ in confirmedICloud = false }
                        Text("系统只提供 CalDAV 类型，其他服务也可能在列表中。请核对所选账户确实为 iCloud。")
                            .font(.system(size: 12)).foregroundStyle(Crayon.muted)
                        Toggle("我确认所选账户是我的 iCloud 提醒事项账户", isOn: $confirmedICloud)
                        Button("创建全新的专用清单") { Task { await model.createList(accountID: accountID) } }
                            .buttonStyle(CrayonButton(fill: Crayon.red, foreground: .white)).disabled(accountID.isEmpty || !confirmedICloud || model.busy)
                        Text("默认名称“小新待办”。同名清单存在时使用新名称，不接管原清单。")
                            .font(.system(size: 12)).foregroundStyle(Crayon.muted)
                    }
                } else {
                    HStack(spacing: 15) {
                        Button(model.calendarID == nil ? "连接苹果提醒事项" : "重新检查连接") { Task { await model.connect() } }
                            .buttonStyle(CrayonButton(fill: Crayon.red, foreground: .white)).disabled(model.busy)
                        if model.phase == .unavailable { Button("重新设置新清单", action: onReset).buttonStyle(CrayonButton(fill: Crayon.paper)).disabled(model.busy) }
                        if model.busy || model.loading { ProgressView().controlSize(.small) }
                    }
                }
                Text("不需要另外注册账号，也不会把任务上传到第三方服务。iCloud 设置与系统授权由你操作。")
                    .font(.system(size: 12)).foregroundStyle(Crayon.muted)
            }.padding(35).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Crayon.cream)
    }
}
