# shinchan-todo 工程基线

- 核对日期：2026-10-29。
- 基线：`main@ec5812c40b73b6befeaa7391e5894a37f1e16431`（文档补录前提交）。
- 来源：本仓库已提交源码、测试和现有说明；不纳入其他工作区未提交或未合并能力。
- 范围：只补文档和流程，不改变业务、依赖、数据或部署。

## 能力与证据

| 验收目标 | 源码 | 既有验证入口 |
| --- | --- | --- |
| 读写只在绑定清单内，拒绝失权/丢失清单/版本冲突 | `Sources/TodoCore/ReminderService.swift`、`Sources/TodoSystem/EventKitBackend.swift` | `Tests/TodoCoreTests/ServiceTests.swift`、`ControllerTests.swift` |
| 原生重复规则映射与安全编辑 | `Sources/TodoCore/TaskRepeat.swift`、`Sources/TodoSystem/ReminderRecurrence.swift` | `Tests/TodoCoreTests/RepeatTests.swift` |
| 计时暂停恢复、完成去重、日期统计 | `Sources/TodoCore/FocusModel.swift`、`FocusController.swift` | `Tests/TodoCoreTests/FocusTests.swift`、`FocusControllerTests.swift` |
| JSON 损坏/保存失败保护、摘要保留原备注 | `Sources/TodoSystem/FocusStore.swift`、`Sources/TodoCore/FocusNotes.swift`、`ReminderService.swift` | `FocusTests.swift`、`FocusControllerTests.swift` |
| 演示隔离、通知生命周期 | `Sources/TodoSystem/DemoBackend.swift`、`FocusNotifications.swift` | `Tests/TodoCoreTests/FocusNotificationTests.swift` 与历史人工验收 |

## 最短启动与检查

`Package.swift` 声明 macOS 14、Swift tools 6.0，Swift 5 语言模式，无第三方包依赖。需要已有 macOS/Swift 命令行工具；在根目录运行 `bash scripts/test.sh`，再运行 `bash scripts/build-app.sh`，打开 `dist/小新待办.app`。测试脚本执行 CoreChecks 可执行断言程序，不是 `swift test`；构建脚本完成 release build、资源组装、ad-hoc 签名及校验。

优先选择纯内存演示。真实接入需要用户显式授权完整提醒事项权限、确认账户并新建专用清单；本次未读绑定信息、Focus.json 或私人任务。测试数据使用虚构标题与独立清单，不能拿真实提醒事项当自动化夹具。

## 验收清单与边界

- [ ] 绑定清单创建、失效、权限撤销与跨清单拒绝。
- [ ] 外部修改时冲突拒绝并保留草稿；高级日期和不支持重复规则不覆盖。
- [ ] 专注完成、暂停、重启、文件损坏、摘要失败与原备注保留。
- [ ] 真实 EventKit 写入、苹果重复实例生成、iPhone 同步分别核验。
- [ ] macOS 14 真机、通知、休眠恢复及分发签名独立验收。

EventKit 保存前版本检查不是跨设备原子锁。任务草稿未持久化；专注记录只在本机，不提供独立云同步。README 历史下载为 0.3.1，源码 0.4.0 的发布资产本次未核验。角色素材来源与使用边界继续见既有 AssetSources 文档；仓库未选定开源许可证，不承诺角色商业授权。

## 本次验证记录

- 已执行：OpenSpec 1.14.2 全量严格格式校验、`git diff --check`、新改 Markdown 相对路径核对及命令来源静态核对，结果见本次 PR。
- 未执行：业务测试、依赖安装、服务启动、真实平台集成、收费模型调用、发布/部署。仅文档变更不将源码审阅表述为运行通过。
- 后续功能验收应运行上文对应测试，并补正常、边界和失败路径证据；外部系统与真实设备需另行授权及验证。

## 文档分工

[README](../README.md) 是用途与启动入口；[AGENTS](../AGENTS.md) 约束修改流程；[OpenSpec](../openspec/README.md) 区分当前能力与未来变更。旧文档中的已验证结论保留其原时间与上下文，不作为当前生产证据。
