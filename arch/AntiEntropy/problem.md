# Problem Issues

> 记录日期：2026-05-13
> 更新日期：2026-05-14
> 状态：部分修复，部分仍为审计记录。
> 范围：跨对话记忆系统的设计可靠性与当前实现风险。

## 审计边界

本文件记录"高概率影响用户体感"的问题，不等同于已验证 bug ticket。当前结论来自源码与 arch 文档对照以及 `xcodebuild test` 验证。

2026-05-13 追加：`arch/modules/background/` 已记录 BackgroundWorker / LibMan / 世界书向量化的目标架构规划。该规划尚未实现，不能作为当前源码行为引用。

2026-05-13 追加：`arch/modules/stage/` 已记录 Stage / 多角色参与 / Director 三模式的目标架构规划。该规划尚未实现，不能作为当前源码行为引用。

2026-05-13 追加：`arch/modules/memory/hindsight-lite.md` 已从概念页扩展为轻量 retain / recall / reflect 完善设计。该设计用于指导剩余 memory problem 的修复，但除已存在的 retain v1 和本地 semantic recall 外，provenance、recall trace、fallback tiers、reflect observation 均尚未实现。

2026-05-14 追加：Phase A recall ordering 已落地，`PromptAssembler.trim(memories:)` 不再按 `importance` 重排，保留 `MemoryManager` 输出的 retrieval order。

2026-05-14 追加：Memory Hindsight-lite 计划包的边界已澄清：当前只补 Memory 层 retain / recall / fallback / provenance / reflect contract。世界书向量化和 BackgroundWorker 统一调度属于后续独立计划包，不作为当前 Memory 包验收项。

相关主链路：

`ChatViewModel.generateResponse(...) -> MemoryManager.extractMemories(...) [前置同步] -> MemoryManager.retrieveMemories(...) -> PromptAssembler.preview(...) -> ContextManager.prepareHistory(...) -> PromptAssembler.assemble(...) -> APIClient.streamMessage(...)`

后台提取链路（onDisappear）：

`ChatViewModel.triggerMemoryExtraction() -> MemoryManager.extractMemories(from:) -> APIClient.sendMessage(...) -> EmbeddingProvider.embed(...) -> MemoryVectorStore.insert(entries:)`

## 记忆系统 problem 风险

| 优先级 | 问题 | 影响 | 主要证据 | 状态 |
|---|---|---|---|---|
| ~~P1~~ | ~~增量提取 cutoff 使用 `memory_entry.createdAt`，不是已处理 message 边界~~ | ~~后台提取期间产生的新消息可能被永久跳过~~ | 已修复：cutoff 改为 `conversation.lastExtractedSortOrder`（message sortOrder 边界），v13 migration 追加列。`MemoryExtractionCutoffTests` 覆盖 sortOrder 边界、并发消息不被跳过。 | **Closed** |
| ~~P1~~ | ~~自动提取触发依赖 ViewModel 内存计数和 `onDisappear`~~ | ~~页面重建、异常退出、短会话、失败流式响应都可能导致不提取~~ | 已修复：`generateResponse` 改为按 DB 中 `conversation.lastExtractedSortOrder` 计算待提取消息数，达到 `minimumPendingMessagesForExtraction` 后前置同步等待提取；UI 通过 `MemoryExtractionPhase` 驱动内联指示器显示提取状态。`ChatView.onDisappear` 保留兜底。`ChatViewModelPromptAssemblyTests` 覆盖 ViewModel 重建后仍按持久 sortOrder 边界触发提取。 | **Closed** |
| ~~P1~~ | ~~语义检索顺序在 Prompt 注入前被 importance 重排~~ | ~~当前输入最相关的记忆可能被高 importance 但低相关记忆挤掉~~ | 已修复：`PromptAssembler.trim(memories:)` 按输入数组顺序裁剪，不再执行 importance 降序排序；`PromptAssemblerTests.test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 覆盖高 importance 第三条被预算裁掉时 A/B retrieval order 仍保留。 | **Closed** |
| P2 | fallback 和距离阈值缺少校准与可观测性 | 用户可能看到"不相关记忆被塞入"或"相关记忆没命中"，且 UI 难以解释 | `distanceThreshold == 1.5`；embedding/vector 异常和空/低相关结果都会 fallback 到 recent memories；`hindsight-lite.md` 已规划 `MemoryRecallTrace` 与 fallback tiers | Open |
| P2 | recent fallback 只按时间取最近 N 条 | 低相关或近期噪声可能进入 prompt，summary/relationship 等高价值记忆没有类型优先级 | `MemoryManager.retrieveRecentSummary(...)` 最终调用 `DatabaseManager.fetchRecentMemories(...)`，仅按 `createdAt` 倒序；Hindsight-lite 规划改为 keyword + recent high-value 分层 fallback | Open |
| P2 | 提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束 | 记忆内容容易泛化、重复或不贴角色关系状态 | `MemoryManager.callExtractionAPI(...)` 只发送 `role: content` 拼接文本与通用 JSON 提取规则；Hindsight-lite 规划 retain v2 与 `memory_entry_provenance` | Open |
| P2 | Responses API 会合并 system messages 到 `instructions` | `[Memories]` 的实际请求位置不再严格等于 Chat Completions message 序列中的 Current-Turn Context | `ResponsesAPIRequest.init(...)` 将所有 `system` message join 到 `instructions`，只保留非 system message 在 `input` | Open |
| P2 | Background 目标架构尚未落地 | WorldBook 与 Memory 仍是两套直接注入逻辑，无法由后台员工统一排序、去重、裁剪 | `arch/modules/background/` 已记录目标；当前源码仍由 `PromptAssembler` 分别处理 world book entries 与 memories。该项留给后续独立 Background / 世界书向量化计划，不阻塞当前 Memory 层完善包。 | Planned |
| P2 | Stage 目标架构尚未落地 | 当前 Chat 仍是单主角色对话，不支持多角色同场、导演模式或用户导演输入 | `arch/modules/stage/` 已记录目标；当前源码仍是 `ChatViewModel` + 单 conversation 生成链路 | Planned |
| ~~P3~~ | ~~记忆提取/检索可观测性不足~~ | ~~用户很难判断"没生成""没检索到""被预算裁掉"还是"模型忽略了"~~ | 部分修复：提取阶段已通过 `MemoryExtractionIndicator` 显示 extracting/completed/failed 状态。检索阶段的候选记忆 distance、fallback 原因和预算裁剪结果仍未在 UI 展示。 | **Partial** |

## 建议修复顺序（剩余）

1. 引入 `MemoryRecallResult` / `MemoryRecallTrace`，把候选数、distance、fallback 原因、selected ids 和 omitted ids 记录下来。
2. 把 recent fallback 改为 keyword + recent high-value 分层 fallback，避免近期噪声无条件进入 prompt。
3. 优化提取 prompt：加入角色卡摘要、已有记忆摘要、source message 范围、去重要求与更严格 JSON schema。
4. 追加 Hindsight-lite provenance schema，再考虑低频 reflect observation。
5. 独立计划包：世界书向量化。
6. 独立计划包：BackgroundWorker / BackgroundPacket 统一调度。

## 三边一致性待办

| 边 | 当前状态 | 待补动作 |
|---|---|---|
| `arch-src` | 部分已修复 | `arch/modules/memory/` 已拆分为架构、数据模型、embedding/vector、提取、检索/prompt、UI、测试和 Hindsight-lite 规划文档；cutoff 边界、提取触发、recent fallback 现实、retrieval-order-preserving prompt trim 和 Hindsight-lite 完善设计已回写。Memory 包边界已澄清为不实现世界书向量化或 BackgroundWorker。Responses API system folding 仍需更新。 |
| `arch-test` | 部分已修复 | cutoff 边界、提取 phase、migration、发送链路持久 sortOrder 触发、PromptAssembler memory trim 保序已有测试覆盖。fallback tiers、recall trace、provenance 和 reflect observation 测试仍待补。 |
| `src-test` | 部分已修复 | 2026-05-14 Phase A focused suite 35 tests / 4 suites 通过；full suite 219 tests / 45 suites 全部通过。 |

## 验证建议

修复或验证这些问题时，建议至少运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

随后运行 full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
