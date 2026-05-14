# 00. 缺口矩阵

本页只记录当前源码对照后的事实，不把 Hindsight-lite 规划误写成已实现能力。

## 源码锚点

| 关注点 | 当前源码 / 测试 |
|---|---|
| 发送链路提取与检索 | `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` |
| retain / recall 编排 | `OpenChat/Core/Memory/MemoryManager.swift` |
| vector search / atomic write | `OpenChat/Core/Memory/VectorStore.swift` |
| memory DB CRUD | `OpenChat/Core/Database/DatabaseManager+Memory.swift` |
| memory record | `OpenChat/Core/Database/Records/MemoryEntryRecord.swift` |
| migrations | `OpenChat/Core/Database/Migrations.swift` |
| prompt trim / injection | `OpenChat/Core/PromptEngine/PromptAssembler.swift` |
| Responses API request shape | `OpenChat/Core/Networking/ResponsesAPIRequest.swift` |
| retrieval tests | `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift` |
| prompt tests | `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` |

## AE 问题状态对照

| AE 条目 | 当前源码状态 | 缺什么 | 计划阶段 |
|---|---|---|---|
| P1 retrieval order 被 importance 重排 | 已修复：`MemoryManager.retrieveMemories(...)` 恢复 KNN id 顺序，`PromptAssembler.trim(memories:)` 按输入数组顺序裁剪，不再按 `importance DESC` 排序 | `PromptAssemblerTests.test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 锁定输入顺序不会被 importance 覆盖 | Phase A completed |
| P2 fallback / threshold 不可解释 | `distanceThreshold == 1.5`；semantic fail 或 no hit 直接 recent fallback；只有日志 | `MemoryRecallTrace`、候选数、distance、fallback reason、selected / omitted ids | Phase B |
| P2 recent fallback 只按时间 | `fetchRecentMemories(...)` 只按 `createdAt DESC`，`retrieveRecentSummary` 名称也会误导 | keyword candidate、recent high-value candidate、empty index 与 semantic unavailable 分流 | Phase B |
| P2 extraction prompt 缺 source / dedupe | `callExtractionAPI(...)` 输入是 `role: content`；`ExtractedMemory` 只有 `content/type/importance` | message id / sortOrder 输入、character summary、existing memory hints、v2 output、同批 dedupe | Phase C |
| P2 缺 provenance schema | `memory_entry` 扁平；没有 source range、tags、dedupeKey、confidence、promptVersion | v14+ `memory_entry_provenance` companion table 与 GRDB record/CRUD | Phase C |
| P2 Responses system folding | `ResponsesAPIRequest.init(...)` 把 system messages join 到 `instructions` | request shape tests；arch/api-client 记录 `[Memories]` folding 影响；Background label 稳定性留给后续 Background 计划包 | Phase D |
| P3 retrieval 可观测性 partial | Chat UI 只展示 extraction phase；recall 失败只进日志 | debug-facing recall trace，不进入主 prompt | Phase B/D |

## 已关闭项，不纳入本轮实现

| 历史问题 | 当前证据 |
|---|---|
| cutoff 使用 `memory_entry.createdAt` | `conversation.lastExtractedSortOrder` 已存在，`MemoryExtractionCutoffTests` 覆盖 |
| 自动提取依赖 ViewModel 内存计数 / onDisappear | `generateResponse(...)` 已按 DB pending count 前置同步提取，`onDisappear` 只是兜底 |
| 半索引 memory | `VectorStore.insert(entries:)` 原子写入，失败回滚；`MemoryManagerRetrievalTests` 覆盖 |
| semantic retrieval fail 后 Chat 直接空 memory | `MemoryManager.retrieveMemories(...)` 内部 fallback；Chat 只记录 fallback 仍失败的 warning |

## 当前实现细节风险

- `retrieveRecentSummary(...)` 名称含 `Summary`，但实际没有筛选 `.summary` 类型。改 fallback tier 时建议改名或保留兼容 wrapper。
- `PromptAssembler` 目前无法记录预算裁剪 dropped ids；本计划可先在 Memory recall trace 中记录 recall selected，prompt budget omission 只做当前 `[Memories]` 形态的验收记录，统一 Background 裁剪留给后续 Background 计划包。
- `MemoryVectorStore.search(...)` 协议只返回 `(entryId, distance)`，可支持 semantic trace；keyword/recent candidate 不需要改 vector store。
- `MemoryEntryRecord` 继续作为 prompt 注入稳定内容表，Hindsight-lite metadata 应优先 companion table，避免破坏管理 UI。
- `ResponsesAPIRequest` 的 folding 是 provider adapter 行为，不是 memory 模块单独能修掉的问题；本轮只测试和文档化当前 `[Memories]` 形态，不决定未来 Background block 形状。
