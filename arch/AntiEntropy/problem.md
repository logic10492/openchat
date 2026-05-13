# Problem Issues

> 记录日期：2026-05-13
> 更新日期：2026-05-13
> 状态：部分修复，部分仍为审计记录。
> 范围：跨对话记忆系统的设计可靠性与当前实现风险。

## 审计边界

本文件记录"高概率影响用户体感"的问题，不等同于已验证 bug ticket。当前结论来自源码与 arch 文档对照以及 `xcodebuild test` 验证。

相关主链路：

`ChatViewModel.generateResponse(...) -> MemoryManager.extractMemories(...) [前置同步] -> MemoryManager.retrieveMemories(...) -> PromptAssembler.preview(...) -> ContextManager.prepareHistory(...) -> PromptAssembler.assemble(...) -> APIClient.streamMessage(...)`

后台提取链路（onDisappear）：

`ChatViewModel.triggerMemoryExtraction() -> MemoryManager.extractMemories(from:) -> APIClient.sendMessage(...) -> EmbeddingProvider.embed(...) -> MemoryVectorStore.insert(entries:)`

## 记忆系统 problem 风险

| 优先级 | 问题 | 影响 | 主要证据 | 状态 |
|---|---|---|---|---|
| ~~P1~~ | ~~增量提取 cutoff 使用 `memory_entry.createdAt`，不是已处理 message 边界~~ | ~~后台提取期间产生的新消息可能被永久跳过~~ | 已修复：cutoff 改为 `conversation.lastExtractedSortOrder`（message sortOrder 边界），v13 migration 追加列。`MemoryExtractionCutoffTests` 覆盖 sortOrder 边界、并发消息不被跳过。 | **Closed** |
| ~~P1~~ | ~~自动提取触发依赖 ViewModel 内存计数和 `onDisappear`~~ | ~~页面重建、异常退出、短会话、失败流式响应都可能导致不提取~~ | 已修复：提取从响应后异步触发改为下次 `generateResponse` 中前置同步等待；UI 通过 `MemoryExtractionPhase` 驱动内联指示器显示提取状态。`ChatView.onDisappear` 保留兜底。 | **Closed** |
| P1 | 语义检索顺序在 Prompt 注入前被 importance 重排 | 当前输入最相关的记忆可能被高 importance 但低相关记忆挤掉 | `MemoryManager.retrieveMemories` 按 KNN id 顺序恢复结果；`PromptAssembler.trim(memories:)` 再按 `importance` 降序排序 | Open |
| P2 | fallback 和距离阈值缺少校准与可观测性 | 用户可能看到"不相关记忆被塞入"或"相关记忆没命中"，且 UI 难以解释 | `distanceThreshold == 1.5`；embedding/vector 异常和空/低相关结果都会 fallback 到 recent memories | Open |
| P2 | 新对话 recent summary 设计与实现不一致 | 文档承诺 summary 优先，但实际只是最近 N 条，降低跨对话连续性稳定性 | `arch/modules/memory/index.md` 写"优先返回 type == .summary"；`DatabaseManager.fetchRecentMemories` 仅按 `createdAt` 倒序 | Open |
| P2 | 提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束 | 记忆内容容易泛化、重复或不贴角色关系状态 | `MemoryManager.callExtractionAPI(...)` 只发送 `role: content` 拼接文本与通用 JSON 提取规则 | Open |
| P2 | Responses API 会合并 system messages 到 `instructions` | `[Memories]` 的实际请求位置不再严格等于 Chat Completions message 序列中的 Current-Turn Context | `ResponsesAPIRequest.init(...)` 将所有 `system` message join 到 `instructions`，只保留非 system message 在 `input` | Open |
| ~~P3~~ | ~~记忆提取/检索可观测性不足~~ | ~~用户很难判断"没生成""没检索到""被预算裁掉"还是"模型忽略了"~~ | 部分修复：提取阶段已通过 `MemoryExtractionIndicator` 显示 extracting/completed/failed 状态。检索阶段的候选记忆 distance、fallback 原因和预算裁剪结果仍未在 UI 展示。 | **Partial** |

## 建议修复顺序（剩余）

1. 修检索排序：保留 KNN relevance 顺序，`importance` 只作为 tie-breaker 或预算裁剪权重。
2. 增加调试可见性：至少在详细统计或开发开关下显示本轮候选记忆、distance、fallback 原因和预算裁剪结果。
3. 优化提取 prompt：加入角色卡摘要、已有记忆摘要、source message 范围、去重要求与更严格 JSON schema。

## 三边一致性待办

| 边 | 当前状态 | 待补动作 |
|---|---|---|
| `arch-src` | 部分已修复 | `arch/modules/memory/index.md` 已更新 cutoff 边界和提取触发时机。recent summary 和 Responses API system folding 仍需更新。 |
| `arch-test` | 部分已修复 | cutoff 边界、提取 phase、migration 已有测试覆盖。ranking、fallback 可解释性的端到端测试仍待补。 |
| `src-test` | 部分已修复 | 217 tests / 45 suites 全部通过（含新增 `MemoryExtractionCutoffTests` 和 `MemoryExtractionPhaseTests`）。 |

## 验证建议

修复或验证这些问题时，建议至少运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

随后运行 full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
