# 专用提醒事项清单基线

## Purpose

依据 `Sources/TodoCore/ReminderService.swift`、`Sources/TodoSystem/EventKitBackend.swift` 与 `Tests/TodoCoreTests/ServiceTests.swift` 记录当前数据边界。

## Requirements

### Requirement: 绑定清单范围

应用 SHALL 在读取和写入前验证权限、清单存在及可写，并限定绑定清单。

#### Scenario: 有效清单读取
- **WHEN** 权限有效且绑定清单存在并可写
- **THEN** EventKit 查询仅传入该清单，并复核返回任务的归属

#### Scenario: 清单失效或权限丢失
- **WHEN** 绑定清单不存在、只读或权限不再授权
- **THEN** 服务拒绝操作，不按同名清单自动接管

### Requirement: 保存前版本检查

应用 SHALL 在编辑、完成、删除前重读任务并校验清单和期望版本。

#### Scenario: 版本匹配
- **WHEN** 当前任务仍属于绑定清单且版本匹配
- **THEN** 适配器只更新发生变化的支持字段并提交系统保存

#### Scenario: 外部修改冲突
- **WHEN** 当前版本与用户操作时版本不同
- **THEN** 返回 conflict，不覆盖外部修改

#### Scenario: 其他清单任务
- **WHEN** 任务标识对应的真实记录不属于绑定清单
- **THEN** 返回 outsideList，不修改该记录
