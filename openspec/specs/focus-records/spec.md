# 专注与记录基线

## Purpose

依据 `Sources/TodoCore/FocusModel.swift`、`Sources/TodoCore/FocusController.swift`、`Sources/TodoSystem/FocusStore.swift` 和 FocusTests/FocusControllerTests 记录本机专注边界。

## Requirements

### Requirement: 专注完成与恢复

专注计时 SHALL 独立记录完整工作轮次，不自动完成提醒事项；恢复的运行检查点 SHALL 处于暂停状态。

#### Scenario: 工作轮次到零
- **WHEN** 工作计时完整到零
- **THEN** 记录一轮投入并提示后续选择，不调用任务完成操作

#### Scenario: 从运行检查点恢复
- **WHEN** 读取到运行中的专注检查点
- **THEN** 恢复为暂停，需手动继续，不计入应用关闭期间时间

### Requirement: 本地存储失败保护

应用 SHALL 区分读坏文件与保存失败，不能以空记录覆盖损坏文件或把失败称为已保存。

#### Scenario: 存档损坏
- **WHEN** 存档解析或版本校验失败
- **THEN** 控制器进入 storageBlocked，阻止写入并提示重试读取

#### Scenario: 保存失败
- **WHEN** 保存当前存档抛出错误
- **THEN** 暂停计时、取消通知，保留内存内容并标记未保存

#### Scenario: 摘要写入失败
- **WHEN** 提醒事项摘要写入发生权限、版本或系统错误
- **THEN** 显示摘要未写入，保留本地专注记录
