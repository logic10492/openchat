---
description: "Use when working with context management, truncation strategy, checkpoint compression, or the ContextManager type. Covers the 40% budget rule, FIFO truncation, persisted compression checkpoints, and strategy selection."
applyTo: "**/ContextManager/**/*.swift"
---
# 上下文管理规范

## 上下文预算规则

- 发送给模型的总上下文（包括所有 prompt 段 + 历史消息 + 当前输入）不超过 `endpoint.maxContextTokens × 0.40`
- 该比例是硬性上限，不可通过配置突破
- 剩余 60% 留给模型生成和注意力安全余量
- 当会话使用压缩策略时，`conversation.compressionMode` 决定自动压缩阈值取向：
  - `standard`：自动压缩阈值为 `endpoint.maxContextTokens × 0.40`
  - `highIntelligence`：effective compact window 为 `endpoint.maxContextTokens × 0.25`，自动压缩阈值为该 effective window 的 90%

## 策略协议

所有策略实现 `ContextStrategyProtocol`:
```swift
protocol ContextStrategyProtocol {
    func process(allMessages: [MessageRecord], tokenBudget: Int) async throws -> [MessageRecord]
}
```

## 对话剔除 (TruncationStrategy)

- 从最新消息向最旧遍历，累加 token 直到超出预算
- 超出预算后，更早的消息全部丢弃（不包含在返回结果中）
- 始终保留最后一轮完整的 user + assistant 对（允许小幅超预算）
- 被剔除的消息仅不发送给 API，**不从数据库删除**

## 对话压缩 (Checkpoint Compression)

- 压缩不是每轮临时摘要；只有超过 `CompressionPolicy.autoCompactTokenLimit` 时才生成 checkpoint
- `standard` 模式：`autoCompactTokenLimit = endpoint.maxContextTokens × 0.40`
- `highIntelligence` 模式：`effectiveCompactWindowTokens = endpoint.maxContextTokens × 0.25`，`autoCompactTokenLimit = effectiveCompactWindowTokens × 0.90`
- checkpoint 存储于 `conversation_compression_checkpoint`
- checkpoint 必须记录 `sourceStartSortOrder`、`sourceEndSortOrder`、`sourceHash`、`summary`、`createdAt`、`endpointId`、`modelName`
- checkpoint 复用时必须校验 source hash，并且生成时的 `effectiveCompactWindowTokens` / `autoCompactTokenLimit` 必须与当前 `CompressionPolicy` 一致；切换压缩模式后不能复用旧阈值 checkpoint
- 同一段旧消息只压缩一次；后续请求复用最近有效 checkpoint
- 生成新 checkpoint 时只压缩上一个 checkpoint 之后的旧历史段，并将旧 summary 合并进新 summary
- 本轮 prompt 使用 `compressed context + checkpoint 后 message history`
- 压缩成功后才保存 checkpoint；压缩失败时 fallback 到剔除策略，不写入 checkpoint
- 编辑或删除已被 checkpoint 覆盖的消息时，必须删除受影响 checkpoint

## 策略选择

- 每个会话通过 `conversation.contextStrategy` 字段选择策略
- 每个会话通过 `conversation.compressionMode` 字段选择压缩模式；仅当 `contextStrategy == compression` 时生效
- 默认策略由全局设置 `default_context_strategy` 决定
- 策略切换即时生效（下次发送消息时使用新策略）

## 约束

- ContextManager 不直接访问 PromptAssembler（避免循环依赖）
- ContextManager 接收 `fixedTokens` 参数，通过 `CompressionPolicy.historyBudget(fixedTokens:)` 计算历史预算
- 压缩调用是异步的，可能较慢，调用方需要向用户展示加载状态
- 压缩失败时 fallback 到剔除策略，不阻塞发送流程
