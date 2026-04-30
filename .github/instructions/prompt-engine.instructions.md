---
description: "Use when working with prompt assembly, token counting, token budget allocation, or the PromptAssembler/PromptSegment/TokenCounter/TokenBudget types. Covers assembly order, budget rules, and world book injection."
applyTo: "**/PromptEngine/**/*.swift"
---
# Prompt 拼装引擎规范

## 拼装顺序（不可更改）

发送给 API 的 `messages` 数组严格按以下四层顺序:

1. Stable Identity: base system prompt, character description, scenario, slowPlot directive
2. Stable Conversation State: compressed context, checkpoint 后 history
3. Current-Turn Context: example dialogs block, world book entries block, memories block
4. Current Turn: current user input + `[Time] <ISO8601> [/Time]`

其中：
- 示例对话必须以 `[Example Dialogs]` labeled `system` block 注入，不作为真实 `user/assistant` 历史。
- 世界书条目必须统一进入 `[World Book Entries]` block；`after_system` / `before_history` 只作为旧数据兼容字段，不决定最终位置。
- 记忆必须统一进入 `[Memories]` block。
- 时间上下文必须跟随当前输入放在最后一条 `user` message 内，不再作为独立 `system` message。

## Token 预算

- 总预算 = `endpoint.maxContextTokens × 0.40`
- 固定段（Stable Identity、Current-Turn Context、Current Turn）按实际 token 计算，不可压缩
- 示例对话上限 = 剩余预算 × 25%
- 世界书上限 = 剩余预算 × 35%
- 记忆上限 = 剩余预算 × 15%
- 历史消息 = 剩余预算 - 示例实际 - 世界书实际 - 记忆实际
- token 紧张时优先裁剪示例对话，其次世界书低优先级条目

## Token 计数

使用近似算法（`TokenCounter.count()`）：
- ASCII 字符: 每 4 字符 ≈ 1 token
- CJK 字符: 每字符 ≈ 1.5 token
- 每条 message 额外 +4 token（role 标记开销）
- 允许与 tiktoken 有 ±15% 误差

## 世界书注入规则

- 仅注入关键词匹配命中且 `isEnabled` 的条目
- 关键词匹配基于当前输入 + 最近 5 条消息的文本
- CJK 关键词: 子串匹配（大小写不敏感）
- 英文关键词: 全词匹配（前后为空格/标点/行首行尾）
- 条目按 priority 降序注入，超出 token 预算时停止

## PromptAssembler 约束

- `assemble()` 是纯函数（给定相同输入，输出相同）
- 不直接访问数据库（由调用方传入所有数据）
- 返回 `AssemblyResult`，包含 messages + tokenUsage + triggeredEntries 三部分
- 角色描述拼接时跳过 nil/空字段，不生成空行

## 两阶段调用

外部调用方（ChatViewModel）需遵循两阶段调用：
1. 阶段 1: `PromptAssembler` 计算固定段 token → 得到 fixedTokens
2. 阶段 2: `ContextManager` 用 fixedTokens 处理历史 → 得到 processedHistory
3. 阶段 3: `PromptAssembler` 用 processedHistory 完成最终拼装

不允许跳过阶段或一次调用完成全部工作。
