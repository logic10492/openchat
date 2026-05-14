# 02. DAG 与文件归属

## 阶段 DAG

```text
S0 baseline
  -> A recall ordering
  -> B1 recall DTO + trace
  -> B2 fallback tiers + keyword/recent high-value
  -> C1 provenance migration + record
  -> C2 extraction prompt v2 + parser compatibility
  -> C3 dedupe/reinforce minimal behavior
  -> D1 reflect observation contract
  -> D2 Responses API [Memories] request shape tests
  -> Lead docs / AE / harness closeout
```

可并行窗口：

- A 必须先做，因为它定义 PromptAssembler 的排序契约。
- B1 与 B2 可由同一 worker 连续做，避免 DTO 震荡。
- C1 可在 B1 后并行准备 migration / DB record，但 C2/C3 需要 C1。
- D2 可在 A 后独立做当前 `[Memories]` request shape 测试，不依赖 provenance。
- Lead closeout 必须最后做，不能提前把 planned 状态写成 implemented。

不在本 DAG 内：

- 世界书向量化、`world_book_entry_embedding`、`WorldBookBackgroundSource`。
- `Core/Background`、`BackgroundWorker`、`BackgroundPacket`。
- `PromptAssembler` 切换到消费 Background 输出。

这些属于后续独立计划包；本计划只要求 Memory 层输出未来可包装为 Background source/tool。

## 文件归属

| 阶段 | 主要文件 | 测试文件 | 文档写回 |
|---|---|---|---|
| A | `OpenChat/Core/PromptEngine/PromptAssembler.swift` | `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` | `arch/modules/memory/retrieval-prompt.md`, `arch/AntiEntropy/problem.md` |
| B | `OpenChat/Core/Memory/MemoryManager.swift`, `OpenChat/Core/Database/DatabaseManager+Memory.swift` | `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift` | `arch/modules/memory/retrieval-prompt.md`, `arch/modules/memory/testing.md` |
| C1 | `OpenChat/Core/Database/Migrations.swift`, new provenance record / CRUD files | `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`, DB memory tests | `arch/modules/memory/data-model.md` |
| C2/C3 | `OpenChat/Core/Memory/MemoryManager.swift`, possible new DTO files | `OpenChatTests/Core/MemoryExtractionParsingTests.swift`, memory extraction tests | `arch/modules/memory/extraction.md`, `arch/modules/memory/hindsight-lite.md` |
| D1 | new reflect DTO/service if implemented | new memory reflect tests | `arch/modules/memory/hindsight-lite.md`, `arch/modules/memory/ui-management.md` |
| D2 | `OpenChat/Core/Networking/ResponsesAPIRequest.swift` tests only unless behavior changes | `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`, Chat request tests | `arch/modules/api-client.md`, `arch/AntiEntropy/problem.md` |
| Closeout | docs only | full suite evidence | `arch/AntiEntropy/triangle-consistency.md`, `arch/AntiEntropy/propagation-audit.md`, `harness/...` |

## 约束

- 不修改签名配置，不运行会重写签名的手工 Xcode GUI 操作。
- migration 只追加 v14+，不得改 v1-v13。
- 所有 DB 操作用 GRDB Record 或现有 `DatabaseManager` 扩展；sqlite-vec virtual table 的必要 SQL 例外沿用现有 `VectorStore` 风格。
- ViewModel 继续通过 init 接收 `MemoryManager`，不在 View 中直接访问 DB / network。
- 不新增 `Core/Background` 源码依赖；Background adapter 只作为后续计划边界记录。
- 新增 UI 文案进入 `Localizable.xcstrings`；debug-only trace 若暂不展示，可先不加 UI。
