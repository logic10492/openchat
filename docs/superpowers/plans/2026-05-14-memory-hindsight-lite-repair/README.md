# OpenChat Memory Hindsight-lite 改造计划包

> 生成日期：2026-05-14
> 范围：`arch/modules/memory/index.md` 与 `arch/AntiEntropy/problem.md` 中剩余 Memory 问题的源码对照、缺口拆解和实现计划。
> 状态：Phase A/B/C/D 已实施并验证；Lead closeout full suite 已通过。

## 范围边界

本计划包只补完 Memory 层本身：retain、recall、fallback、trace、provenance、dedupe / reflect 的最小 contract，以及当前 `[Memories]` 请求形态验收。

不纳入本计划包：

- 世界书向量化：应另开独立计划包。
- `Core/Background` / `BackgroundWorker` / `BackgroundPacket` 落地：应另开独立计划包。
- `PromptAssembler` 切换到消费 `BackgroundPacket`：应由 Background 计划包处理。

本计划允许把 Memory 输出设计成后续可包装为 Background tool / `MemoryBackgroundSource` 的形状，但不能把 Background 架构写成当前验收项。

## 目标

把当前跨对话 Memory 从“可用的 retain v1 + semantic recall”推进到 Hindsight-lite 的最小可落地形态，同时关闭 `arch/AntiEntropy/problem.md` 仍打开的 Memory 问题：

- P1：Prompt 注入前按 `importance` 重排，破坏语义检索顺序。
- P2：fallback / distance threshold 缺少 trace 和校准证据。
- P2：recent fallback 只按时间取最近 N 条，容易把近期噪声塞入 prompt。
- P2：提取 prompt 缺少角色卡、已有记忆、source 边界和 dedupe 约束。
- P2：Responses API system folding 使 `[Memories]` 的实际 provider 位置弱于 Chat Completions message 序列。
- P3 partial：提取 UI 已有状态，但 recall trace、fallback reason、预算裁剪仍不可见。

## 当前源码结论

已实现且不应重复做：

- `conversation.lastExtractedSortOrder` 已替代 `memory_entry.createdAt` 作为提取 cutoff。
- `ChatViewModel.generateResponse(...)` 已在检索前按 DB 边界同步触发提取。
- `VectorStore.insert(entries:)` 已把 `memory_entry` 和 `memory_embedding` 放在同一 GRDB transaction。
- embedding/vector 异常时 `MemoryManager.retrieveMemories(...)` 已通过 Phase B fallback 到 keyword + recent high-value。
- Chat 内联已有 `MemoryExtractionPhase` / `MemoryExtractionIndicator` 展示提取状态。
- 2026-05-14 Phase A 已完成：`PromptAssembler.trim(memories:)` 按输入 retrieval order 裁剪，不再按 `importance DESC` 重排；`PromptAssemblerTests.test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 覆盖该行为。
- 2026-05-14 Phase B 已完成：新增 `MemoryRecallResult` / `MemoryRecallTrace`，`retrieveMemories(...)` 兼容调用 `recallMemories(...)`；fallback 改为 semantic / keyword / recent high-value tiers；focused suite 49 tests / 5 suites passed。
- 2026-05-15 Phase C 已完成：追加 `memory_entry_provenance`（v14 migration）、`MemoryEntryProvenanceRecord`、provenance CRUD；extraction prompt 改为结构化输入（character + existing hints + message ids/sortOrder）；`ExtractedMemory` 扩展 v2 字段；同批 dedupe、source range validation、sourceMessageIds 过滤、atomic entry+embedding+provenance 写入；focused suite 107 tests / 7 suites passed；full suite 244 tests / 45 suites passed。
- 2026-05-16 Phase D 已完成最小 contract / request-shape 验收：新增 `MemoryReflectModels.swift`，锁定 reflect request / observation / relation contract；新增 Responses API `[Memories]` folding 测试与 Chat Responses 端到端 request 捕获测试；reflect contract 5 tests / 1 suite passed；Responses API suites 21 tests / 5 suites passed；Chat + MemoryReflect focused 17 tests / 2 suites passed。
- 2026-05-16 Lead closeout 已完成：`MemoryManagerRetrievalTests` 改为注入 `InMemoryAPIKeyStore()`，避免 full suite 并发跑测试时触碰真实 Keychain 导致 `-25299`；focused 15 tests / 1 suite passed；full suite 251 tests / 46 suites passed。

仍缺失且属于本计划范围：

- 无。当前 Memory Hindsight-lite 计划包内的 A/B/C/D 与 Lead closeout 已完成。

不属于本计划继续扩展的剩余项：

- reflect LLM executor / UI 入口尚未实现；当前只落地 Memory 层 DTO contract。
- `memory_entry_link` 持久化表尚未追加；`MemoryEntryLinkRelation` 只定义第一版 relation contract，schema 留给后续独立 migration。

## 阅读顺序

1. `00_gap_matrix.md`：arch / AE / source / test 对照，列出实际缺口。
2. `01_target_architecture.md`：Hindsight-lite 改造后的最小目标形态和非目标。
3. `02_dag_and_file_ownership.md`：阶段 DAG、并行边界和文件归属。
4. `03_phase_a_recall_ordering.md`：先关闭 P1 sorting 问题。
5. `04_phase_b_recall_trace_fallback.md`：引入 recall result / trace / fallback tier。
6. `05_phase_c_retain_v2_provenance.md`：追加 provenance schema、extraction prompt v2、dedupe。
7. `06_phase_d_reflect_background_responses.md`：低频 reflect、后续 Background 适配边界、Responses API memory request shape。
8. `07_testing_acceptance.md`：focused tests、full suite、arch/AE writeback 验收。

## 推荐执行顺序

```text
S0 baseline read + focused tests
  -> A recall ordering
  -> B recall result + fallback tiers
  -> C retain v2 provenance + dedupe
  -> D reflect contract / Responses memory request shape
  -> Lead closeout: full suite + final evidence
```

Phase A 是最小可先落地的修复，风险低且能直接关闭当前 P1。Phase B 已完成 recall result / fallback tiers。Phase C 是剩余 Memory retain/provenance 改造主体。Phase D 已完成低频 reflect contract、Memory 请求形态验收和后续 Background 适配边界说明，不实现世界书向量化、Background 层、reflect executor 或 `memory_entry_link` 持久化。

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests'
```

完成每个源码阶段后运行对应 focused tests；最终运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

如 `iPhone 17 Pro` 不存在，先用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

并在所有验证记录里使用同一个可用 simulator 名称。
