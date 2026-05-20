# Problem Issues

> 记录日期：2026-05-13
> 更新日期：2026-05-20
> 状态：部分修复，部分仍为审计记录。
> 范围：跨对话记忆系统的设计可靠性与当前实现风险。

## 审计边界

本文件记录"高概率影响用户体感"的问题，不等同于已验证 bug ticket。当前结论来自源码与 arch 文档对照以及 `xcodebuild test` 验证。

2026-05-13 追加：`arch/modules/background/` 已记录 BackgroundWorker / LibMan / 世界书向量化的目标架构规划。2026-05-17 以后 Background source tools、deterministic worker、BackgroundPacket 和 Chat/Prompt compatible switch 已落地；2026-05-20 又追加 Character/ConversationState sources、Stage context filter、LibMan offline draft runtime、idle reflect draft worker 和 retrieval trace UI。统一 `[Background]` block、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review 仍未实现。

2026-05-13 追加：`arch/modules/stage/` 已记录 Stage / 多角色参与 / Director 三模式的目标架构规划。2026-05-19 Stage foundation 已落地：Stage DB、participant binding、speaker metadata、输入栏 director/participant 切换和 deterministic Director runtime 已接入 Chat/Prompt 主链路；2026-05-20 又追加 LLM Director agent、多 speaker parser、Responses Stage snapshot、Stage XCUITest baseline、Stage -> Background filter 和独立 Stage 管理页。

2026-05-13 追加：`arch/modules/memory/hindsight-lite.md` 已从概念页扩展为轻量 retain / recall / reflect 完善设计。该设计用于指导剩余 memory problem 的修复；retain provenance / dedupe 已在 Phase C 落地，reflect 最小 contract 和 Responses request-shape 已在 Phase D 落地。

2026-05-14 追加：Phase A recall ordering 已落地，`PromptAssembler.trim(memories:)` 不再按 `importance` 重排，保留 `MemoryManager` 输出的 retrieval order。

2026-05-14 追加：Phase B recall trace / fallback tiers 已落地。`MemoryManager.recallMemories(...)` 返回 `MemoryRecallResult(entries, trace)`，兼容 `retrieveMemories(...)` 仍返回有序 `[MemoryEntryRecord]`；semantic 失败或无命中时改为 keyword + recent high-value 分层 fallback。

2026-05-14 追加：Memory Hindsight-lite 计划包的边界已澄清：当前只补 Memory 层 retain / recall / fallback / provenance / reflect contract。世界书向量化和 BackgroundWorker 统一调度属于后续独立计划包，不作为当前 Memory 包验收项。
2026-05-15 追加：Phase C retain v2 provenance + dedupe 已落地。`memory_entry_provenance` companion table（v14 migration）、extraction prompt v2 结构化输入、同批 dedupe、source range validation、sourceMessageIds 过滤、原子写入 entry+embedding+provenance。`action == skip` 丢弃，`action == reinforce` 第一版不覆盖旧记忆且不新增重复记忆。
2026-05-16 追加：Phase D reflect contract + Responses request-shape 已落地。`MemoryReflectModels.swift` 定义 request / observation / relation contract，要求 source/basedOn ids 非空；Responses API `[Memories]` folding 已由 request-level 和 Chat 端到端测试覆盖。未实现 reflect LLM executor、UI 入口、`memory_entry_link` migration 或 Background 层。

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
| ~~P2~~ | ~~fallback 和距离阈值缺少校准与可观测性~~ | ~~用户可能看到"不相关记忆被塞入"或"相关记忆没命中"，且 UI 难以解释~~ | 已修复到 Memory / Background trace：`MemoryRecallTrace` 记录候选数、fallback reason、selected ids 和 omitted；Background diagnostics 已可在 detailed stats trace UI 中展示。普通用户级解释仍可后续优化。 | **Closed** |
| ~~P2~~ | ~~recent fallback 只按时间取最近 N 条~~ | ~~低相关或近期噪声可能进入 prompt，summary/relationship 等高价值记忆没有类型优先级~~ | 已修复：semantic unavailable / no hit 改为 keyword + recent high-value；`DatabaseManager.fetchRecentHighValueMemories(...)` 只取 relationship / summary / `importance >= 70`，Chat 测试覆盖普通 recent 噪声不会进入 request。 | **Closed** |
| ~~P2~~ | ~~提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束~~ | ~~记忆内容容易泛化、重复或不贴角色关系状态~~ | 已修复：`MemoryManager.callExtractionAPI(...)` 改用结构化输入（character summary + existing memory hints + message id/sortOrder）；`ExtractedMemory` 扩展 v2 字段（source range、confidence、tags、dedupeKey、action）；同批 dedupe 保留 importance 更高或 content 更短条目；越界 source range 丢弃，无效 sourceMessageIds 从 provenance 过滤；`skip/reinforce` 不写新记忆；`VectorStore.insert(entries:provenances:)` 原子写入 `memory_entry + memory_embedding + memory_entry_provenance`。`MemoryExtractionParsingTests`、`MemoryManagerRetrievalTests` 覆盖 v2 解析、dedupe、source validation、provenance CRUD。 | **Closed** |
| ~~P2~~ | ~~Responses API 会合并 system messages 到 `instructions`~~ | ~~`[Memories]` 的实际请求位置不再严格等于 Chat Completions message 序列中的 Current-Turn Context~~ | 已验收为 provider adapter 行为：Chat Completions 下 `[Memories]` 仍在 `messages` 中且位于 current turn user 前；Responses 下 `[Memories]` 存在于 `instructions`，非 system `input` 不重复 current input，且 `[Memories]` 不被拼进 user message。Background block request-shape 留给后续独立 Background 计划包。 | **Closed** |
| ~~P2~~ | ~~Background 目标架构尚未落地~~ | ~~WorldBook 与 Memory 仍是两套直接注入逻辑，无法由后台员工统一排序、去重、裁剪~~ | 已进一步关闭：Background source tools、deterministic worker、BackgroundPacket、BackgroundManager、Chat/Prompt compatible switch、Character/ConversationState sources、Stage context filter 和 LibMan offline draft runtime 已落地。剩余统一 `[Background]` block、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review。 | **Partial** |
| ~~P2~~ | ~~Stage 目标架构尚未落地~~ | ~~当前 Chat 仍是单主角色对话，不支持多角色同场、导演模式或用户导演输入~~ | 已进一步关闭：Stage DB/UI foundation、多角色 participant binding、speaker metadata、用户导演输入、deterministic Director runtime、LLM Director agent、多 speaker parser、Responses Stage snapshot、Stage XCUITest baseline、Stage -> Background filter 和独立 Stage 管理页已落地。剩余是更完整 Stage CRUD/editor、流式 multi-speaker parser 和高级 parser diagnostics。 | **Partial** |
| ~~P3~~ | ~~记忆提取/检索可观测性不足~~ | ~~用户很难判断"没生成""没检索到""被预算裁掉"还是"模型忽略了"~~ | 部分修复：提取阶段已通过 `MemoryExtractionIndicator` 显示 extracting/completed/failed 状态；Background diagnostics 已通过 `RetrievalTraceView` 在 detailed stats 下展示。prompt budget 裁剪 omission 仍未完整回写到用户级解释。 | **Partial** |

## 建议修复顺序（剩余）

1. ~~优化提取 prompt：加入角色卡摘要、已有记忆摘要、source message 范围、去重要求与更严格 JSON schema。~~（Phase C 已完成）
2. ~~追加 Hindsight-lite provenance schema，再考虑低频 reflect observation。~~（Phase C 已完成 provenance schema；Phase D 已完成 reflect 最小 contract）
3. ~~Responses API `[Memories]` request-shape 验收。~~（Phase D 已完成当前 `[Memories]` request-shape 验收）
4. 独立计划包：duplicate/conflict review、自动 apply/write 和用户级 retrieval explanation。
5. 独立计划包：统一 `[Background]` block 与 Background request-shape audit。
6. 独立计划包：Stage 完整 CRUD/editor、流式 multi-speaker parser 和高级 parser diagnostics。

## 三边一致性待办

| 边 | 当前状态 | 待补动作 |
|---|---|---|
| `arch-src` | 大部分已修复 | `arch/modules/memory/` 已拆分为架构、数据模型、embedding/vector、提取、检索/prompt、UI、测试和 Hindsight-lite 规划文档；cutoff 边界、提取触发、retrieval-order-preserving prompt trim、recall trace / fallback tiers、retain v2 provenance / dedupe、reflect DTO contract 和 Responses API folding 事实已回写。Memory 包边界已澄清为不实现世界书向量化、BackgroundWorker、reflect executor 或 `memory_entry_link` 持久化。 |
| `arch-test` | 大部分已修复 | cutoff 边界、提取 phase、migration、发送链路持久 sortOrder 触发、PromptAssembler memory trim 保序、fallback tiers、recall trace、provenance migration、v2 parsing、dedupe、source validation、atomic write、reflect contract、Responses request shape、Stage UI baseline 和 Stage Responses snapshot 已有测试覆盖。统一 Background block request-shape 仍待后续计划。 |
| `src-test` | 已修复 | 2026-05-15 Phase C focused suite 107 tests / 7 suites 与 full suite 244 tests / 45 suites 通过；2026-05-16 Phase D reflect contract 5 tests / 1 suite、Responses suites 21 tests / 5 suites、Chat + MemoryReflect focused 17 tests / 2 suites 通过；Lead closeout full suite 251 tests / 46 suites 通过。 |

## 验证建议

修复或验证这些问题时，建议至少运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

随后运行 full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
