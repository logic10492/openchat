---
description: "Use when working with context management, truncation strategy, compression strategy, or the ContextManager type. Covers the 40% budget rule, FIFO truncation, API-based compression, and strategy selection."
applyTo: "**/ContextManager/**/*.swift"
---
# 上下文管理规范

## 40% 预算规则

- 发送给模型的总上下文（包括所有 prompt 段 + 历史消息 + 当前输入）不超过 `endpoint.maxContextTokens × 0.40`
- 该比例是硬性上限，不可通过配置突破
- 剩余 60% 留给模型生成和注意力安全余量

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

## 对话压缩 (CompressionStrategy)

- 最近消息占预算的 70%（保持近期上下文完整）
- 旧消息调用外部 API 压缩为摘要
- 压缩后生成一条 `role: "system"` 的消息: `[Previously: {summary}]`
- 压缩消息设置 `isCompressed: true`，保留 `originalContent`
- **同一段旧消息只压缩一次**（检查是否已有压缩记录）
- 压缩端点可与聊天端点不同（用户在设置中配置）
- 压缩用的 system prompt 格式固定，参见 `arch/modules/context-manager.md`

## 策略选择

- 每个会话通过 `conversation.contextStrategy` 字段选择策略
- 默认策略由全局设置 `default_context_strategy` 决定
- 策略切换即时生效（下次发送消息时使用新策略）

## 约束

- ContextManager 不直接访问 PromptAssembler（避免循环依赖）
- ContextManager 接收 `fixedTokens` 参数，计算 `historyBudget = totalBudget - fixedTokens`
- 压缩调用是异步的，可能较慢，调用方需要向用户展示加载状态
- 压缩失败时 fallback 到剔除策略，不阻塞发送流程
