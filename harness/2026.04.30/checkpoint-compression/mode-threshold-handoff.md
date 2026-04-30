# Compression Mode Threshold Handoff

> 日期：2026-04-30
> 目的：在实施前固定本轮需求和验证边界，降低长对话压缩时的上下文丢失风险。

## 用户要求

当前 checkpoint compression 不应只针对模型名特判固定阈值。压缩阈值应由对话设置选择的 compression mode 决定：

- 标准模式：`endpoint.maxContextTokens * 40%`
- 高智能模式：`endpoint.maxContextTokens * 25% * 90%`

该选择是对话级设置，只影响 `ContextStrategy.compression` 的 checkpoint 生成阈值和历史预算。

## 当前源码入口

- `OpenChat/Core/ContextManager/CompressionPolicy.swift`
  - 现已改为读取 `CompressionMode`，不再按模型名特判阈值。
- `OpenChat/Core/ContextManager/CheckpointCompactor.swift`
  - 使用 `CompressionPolicy(endpoint:)` 判断是否生成/复用 checkpoint，并把 `effectiveCompactWindowTokens` / `autoCompactTokenLimit` 写入 checkpoint record。
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
  - 当前只有 `contextStrategy`，没有 compression mode 字段。
- `OpenChat/Features/Chat/Views/ChatSettingsSheet.swift`
  - 当前只提供 `Context Strategy` picker。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`
  - 当前保存 `contextStrategy`，未保存 compression mode。

## 实施边界

- 新增对话级 `CompressionMode`，raw values：`standard`、`highIntelligence`。
- 新增 `conversation.compressionMode` 字段，默认 `standard`。
- 不修改 `conversation_compression_checkpoint` schema；继续用现有 `effectiveCompactWindowTokens` 和 `autoCompactTokenLimit` 记录生成时 policy。
- checkpoint 复用必须校验当前 policy 的 `effectiveCompactWindowTokens` 和 `autoCompactTokenLimit`，避免切换 mode 后复用旧阈值 checkpoint。
- 更新 arch-test / arch-src / src-test 三边文档和 harness 证据。

## 验证命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/CompressionPolicyTests -only-testing:OpenChatTests/CompressionCheckpointReuseTests -only-testing:OpenChatTests/MigrationTests -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests

xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
