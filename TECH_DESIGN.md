# 小新待办技术设计

## 构建与架构

Swift + SwiftUI + Combine + EventKit + Foundation + UserNotifications + AppKit，最低 macOS 14，无第三方依赖。用 Swift Package Manager 构建核心库、EventKit 适配层和桌面程序；本机构建脚本生成含 Info.plist、权限说明及 ad-hoc 签名的 .app。不自动安装 Xcode、不登录开发者账号、不自动公证。0.3.1 经用户追加批准，可将验证后的 arm64 应用 ZIP 和 SHA256 校验文件发布为 GitHub Release 附件；源码历史继续排除构建产物和个人数据。

核心模块包含任务值对象、查询、统计和限制单清单的服务。EventKit 适配层拥有一个长期存活的 EKEventStore，封装权限、账户元数据、创建清单、查询、获取记录、保存和删除。SwiftUI 状态对象在主线程管理设置、选择、编辑草稿、加载、错误与任务刷新。测试用内存适配器替代系统数据库边界，业务服务与查询逻辑保持真实。

任务快照：EventKit 本地标识、清单标识、标题、备注、日期、原生优先级、完成状态、创建/修改时间、版本签名及日期是否含时间/重复规则。编辑草稿仅携带允许修改的字段。优先级写入原生 0/9/5/1，读取 1–4 为高、5 为中、6–9 为低、0 为无；未修改优先级保留原值。

## 技术选型依据

选型围绕已确认的使用方式：Mac 提供自制原生界面，手机继续操作同一个苹果提醒事项清单。Swift + SwiftUI 负责窗口、表单、快捷键及可访问性；EventKit 负责进入系统提醒事项的数据边界；iCloud 同步由苹果承担。这使首版无需维护独立账号、任务数据库和跨设备同步服务，但仍依赖用户授权、账户配置及苹果同步条件。

共享状态采用系统自带的 Combine / ObservableObject：TodoController 发布任务快照、查询条件、编辑草稿及连接与错误状态，SwiftUI 观察更新。FocusController 独立发布计时、记录、提醒和本地保存状态，两者由应用持有，多个窗口共用一个计时器。当前单清单规模下，这套状态管理已能覆盖共享状态和失败保护；查询、统计放在值对象中，系统访问放在 ReminderBackend 实现中，界面只组织交互。

样式使用 SwiftUI 的布局、颜色、形状、ButtonStyle 与 ViewModifier，统一主题并保留原生输入行为；日期使用 Foundation 的 Calendar 与 DateComponents，同时匹配按日筛选和 EventKit 浮动日期组件。UserDefaults 只持久化清单标识，任务来自系统，草稿和筛选保留内存；0.3.0 专注记录另存本机 JSON；退出前未保存的草稿会丢失。

Swift Package Manager 分模块构建，Bash 使用已有命令行工具组装和验证自用 `.app`。CoreChecks 是当前 CLT 缺少 Swift Testing 运行库时的可执行断言入口，不增加第三方测试依赖；系统数据库使用内存边界替代，真实规则对象可直接验证映射。自动检查的结果与系统权限、真实写入及跨设备验收分开记录。

若后续要求 Windows/浏览器使用、多人协作、独立同步或更复杂的清单关系，需要重新确认平台、数据归属和维护成本，再评估架构；当前首版范围内保持这套最简单的实现。README 的「技术栈与技术选型」和「关键技术点」提供面向项目读者的完整说明。

## 权限与清单创建

显式连接后调用 requestFullAccessToReminders。Info.plist 配置 NSRemindersFullAccessUsageDescription。未授权不查询任务；拒绝、受限或撤销时显示可恢复提示。

EventKit 没有单独的“这是 iCloud”类型。列出具有可写提醒事项清单的 CalDAV 账户元数据，用户明确确认所选账户为 iCloud；不把 Google 等 CalDAV 账户自动当成 iCloud。无候选时提示在系统提醒事项中启用 iCloud 并建立普通清单，再刷新。新清单设置所选 source，保存成功后持久化 calendarIdentifier；同名创建新名称，不接管原清单。

每次操作检查授权、清单存在和可写；每次读取都传入明确的清单集合，不使用 nil 查询全部。单条读取也接收绑定清单标识，在读取正文快照前检查归属；保存前调用 refresh 核对有效记录和版本，跨清单记录一律拒绝。绑定清单消失后阻止全部写入，不自动重建。切换账户会清除用户的 iCloud 确认。

## 编辑、冲突与刷新

编辑/完成/删除提交时重取记录并与用户操作时的版本比较；变化则拒绝覆盖，保留草稿。版本签名由允许编辑字段、完整日期组件、重复规则描述和修改时间构成。显式载入最新时先重新读取单条任务，成功后才替换用户确认放弃的草稿；读取失败或记录删除时保留草稿。

修改现有 EKReminder 对象，仅写入发生变化的字段，保留附件、URL、alarm、未修改的重复规则和其他未覆盖属性；高级日期或重复任务的日期字段只读。

EventKit 不提供带期望版本的原子写入接口，保存前核对不能保证核对与系统写入之间另一设备的同时提交；首版不承诺跨设备原子冲突锁，也不因此引入独立云服务。

EventKit 写入与后续刷新是两个不同结果：写入失败保留草稿；写入已成功但刷新失败提示“已保存，重新加载失败”，不能让用户误认为需重做写入。刷新请求使用代次标识，旧请求不覆盖新请求。EventKit 变化通知、应用激活和本地日历日变更触发重新读取。

日期用 Gregorian 的年/月/日浮动组件保存，不加入时分秒，不设置 EKAlarm。筛选以用户当前时区的本地日为边界，带时间的外部任务保留原日期。统计从未筛选快照计算。

## 界面与资源

三栏使用原生 HSplitView，避免 NavigationSplitView 在嵌套标题布局中插入系统工具栏造成遮挡。侧栏可滚动且支持 Command Option B 折叠；各列设最小宽度，列表和表单独立滚动。

浅色主题：cream #FFF8E7、ink #20212B、red #CE3B3B、sun #F6D66B、sky #C9E8EF。原生表单和语义按钮配合圆角描边；小新 PNG 装饰本地打包，记录生成来源，仅作装饰。控件与文字可用性优先，不让插画遮挡任务。编辑面板有显式保存/取消；切换任务、新建或刷新编辑内容前保护未保存草稿。加载、空列表、无搜索结果、失败与授权状态分别呈现。

0.2.2 补充应用图标：Packaging/AppIcon.png 保存带透明通道的奶油底、小新头像和红色勾选源图。scripts/build-icon.sh 使用系统自带 sips 与 iconutil 生成标准 1x/2x 多尺寸图标，build-app.sh 在签名前复制 AppIcon.icns 到 Contents/Resources，Info.plist 的 CFBundleIconFile 指定该资源。源图、转换脚本和来源记录保留在源码中，图标构建产物位于忽略的 .build/ 与 dist/；不增加 Swift 依赖或运行时图片请求。

## 验证与交付

Swift 自动测试验证日期、组合筛选、搜索、排序、统计、清单范围守卫、冲突、权限撤销和写入失败。打包后验证签名、权限键、资源、最低版本及程序启动。使用可见的演示数据模式检查 UI，演示模式不初始化 EventKit、不读取偏好绑定或真实数据。真实系统授权由用户完成，真实清单及 iPhone 同步验收单独记录。

测试入口为 `bash scripts/test.sh`，运行独立断言程序 CoreChecks；当前 CLT 缺少 Swift Testing 运行库，未使用或宣称 `swift test` 通过。

## 0.2.0 每日规则映射

TaskRepeat 表达 none / daily / other；TaskDraft 包含重复选择，所以只修改重复设置也会触发草稿保护。TaskDraft.validated 同时用于服务与适配器：新建/切换到每日必须有日期；高级日期不修改；不创建或替换 other；已完成或带时间任务不改变重复设置。原有范围、权限、版本检查继续先于写入。

ReminderRecurrence 将单条 daily、interval 1、无结束条件和 BY 筛选的全天规则映射为 daily；其余标记 other 并保持原始对象。写入 daily 使用 EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)，none 写入 nil；编辑仅在重复选择变化时写 recurrenceRules，不因普通备注编辑重建规则。版本签名已覆盖完整重复属性。

完成仍仅设置 isCompleted 并保存，然后读取绑定清单；不计算秒数、不复制记录、不引入额外调度状态。苹果官方说明重复提醒事项只能获取当前第一条未完成记录，完成后下一条可获取。写入后的生成和 iCloud 同步由苹果负责，真实系统行为单独验收。

测试包含真实 EKRecurrenceRule 对象的映射与输出契约，不初始化 EKEventStore；系统数据库边界继续用内存替代。DemoBackend 保持纯内存，只保存设置，不模拟苹果生成。原生日期含具体时间的每日规则视为高级规则。

参考：[苹果重复提醒事项机制](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event)、[原生规则初始化](https://developer.apple.com/documentation/eventkit/ekrecurrencerule/init(recurrencewith:interval:end:))。


## 0.3.0 专注子系统

TodoCore 的 FocusEngine 是注入单调时刻与墙钟日期的纯状态机；FocusRun 保存恢复检查点，FocusRecord 使用会话 UUID 去重，FocusKey 以绑定清单、提醒事项标识和重复任务当次截止日期确定归属。墙钟仅用于日期统计；迟到回调按预计到零时刻归属日期。恢复统一为暂停，不把关闭应用的时间算入学习。

FocusController 独立发布专注状态并调用原有 TodoController 的受限摘要写入接口。计时检查单条原生任务的权限、存在、完成状态和实例归属，不只依赖列表缓存；读取失败停止计时。App 持有唯一控制器与 FocusRuntime，1 秒刷新、5 秒检查点，监听 NSWorkspace 睡眠和 NSApplication 正常退出；窗口切换/关闭不会创建新的专注会话。演示预览有独立内存控制器，关闭即丢弃。

FocusStore 协议由 MemoryFocusStore / FileFocusStore 实现；版本 1 Codable JSON 原子写入应用 Application Support，文件权限 0600，不含任务标题或正文。本地写入失败时退出需确认丢弃未保存的专注记录。包含时长、全量完成记录、当前检查点、待写摘要、休息时长及音效开关。读取损坏停止写入，保存失败暂停并保留内存；完整同步导致任务标识改变时不按名称迁移。

FocusNotes 对【小新专注 v1】与【小新专注结束】之间的可读摘要进行严格解析。Mac 的 TaskDraft 和列表/搜索使用用户备注部分；普通保存从当前版本合并回原摘要。摘要更新只改备注，不改完成状态、日期、优先级或重复规则。无效或多个信息段禁止摘要更新，保留原文。应用自身摘要成功后只更新编辑快照版本，未保存用户草稿保持原样；外部版本变化仍报冲突。

FocusNotifier 由 UserNotifications 系统适配器和纯演示实现组成；显式点击才请求权限，按会话安排一次通知，取消时使异步安排代次失效，并预先登记在途请求，防止旧请求重新出现。正常退出由应用 delegate 等待在途安排结束并取消后才退出。授权失败降级为界面提醒和本机音效，有系统声音请求时不叠加 NSSound。内容不包含任务正文。启动清理遗留本应用通知；系统通知/专注模式造成的静音不宣称应用能绕过。

README 详述使用流程、选型理由和手机/本机数据边界；自动测试使用可执行 CoreChecks，不请求真实权限。不自动安装 Xcode、不增加远程服务或第三方依赖。


## 0.3.1 点击范围与分钟输入

TaskListView 使用 ZStack 中两个兄弟 Button：编辑按钮的 label 包含完整内边距、背景和 RoundedRectangle contentShape，完成圆圈单独放在左上方。描边 overlay 禁用命中，避免视觉边界挡住点击；不通过嵌套 Button 或外层 onTapGesture 混合完成与编辑动作。

FocusCard 使用 String 草稿、FocusState 和 onSubmit 实现输入；FocusDurationInput 仅接受范围内十进制整数，回车、失焦及启动前校验；卡片直接切换销毁时通过 onDisappear 提交有效输入，避免只依赖失焦通知导致丢失。非法值不截断或默默变为默认值，不更新持久化偏好。Stepper 与文本共用同一提交入口；TaskEditorView 按 FocusKey 设置卡片身份，避免切换任务复用上一任务的输入。保存时长可能更新任务摘要版本，启动时使用 TodoController 保留的当前编辑快照，沿用原有版本、范围及权限检查。没有增加依赖或改变 JSON 格式。
