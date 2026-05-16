# 02. DAG 与文件归属

## 阶段 DAG

```text
S0 baseline
  -> A1 schema migrations
  -> A2 WorldBookVectorStore + meta record
  -> B1 embedding text + content hash
  -> B2 WorldBookEmbeddingIndexer
  -> B3 existing world-book rebuild entrypoints
  -> C1 WorldBookRecallModels + WorldBookSource
  -> C2 ChatViewModel + PromptAssembler compatible path
  -> D1 CRUD save / update wiring
  -> D2 import batch wiring
  -> D3 delete / eraseAllData cleanup
  -> Lead docs / harness / full suite closeout
```

可并行窗口：

- A1/A2 必须先做，因为后续 tests 需要 schema 和 vector store。
- B1 可与 A2 并行准备纯函数，但 B2 依赖 A2。
- C1 可在 B2 后实现；C2 依赖 C1。
- D1/D2/D3 可以在 B2 后并行拆，但最终要由 Lead 统一检查事务一致性。
- Lead closeout 最后做，不能提前把 arch 文档写成 implemented。

不在 DAG 内：

- `Core/Background`、`BackgroundWorker`、`BackgroundPacket`。
- Memory / WorldBook 跨 source 全局 fusion。
- 大规模后台调度、任务队列、进度通知中心。

## 文件归属

| 阶段 | 主要源码 | 测试 | 文档写回 |
|---|---|---|---|
| A1 | `OpenChat/Core/Database/Migrations.swift` | `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` | `arch/data-model.md`, `arch/modules/background/world-book-vectorization.md` |
| A2 | new `OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`, new `OpenChat/Core/WorldBook/WorldBookVectorStore.swift`, `DatabaseManager+Content.swift` helpers if needed | new `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift` | `arch/modules/world-book.md` |
| B1 | `WorldBookEmbeddingTextBuilder.swift`, `WorldBookEntryHasher.swift`, `WorldBookError.swift` | new text/hash tests | `arch/modules/background/world-book-vectorization.md` |
| B2/B3 | `WorldBookEmbeddingIndexer.swift`, `DependencyContainer.swift` if injecting shared embedding/indexer | new indexer rebuild tests | `arch/modules/world-book.md`, `arch/modules/memory/embedding-vector-store.md` if shared embedding docs change |
| C1 | `WorldBookRecallModels.swift`, `WorldBookSource.swift`, maybe `KeywordMatcher` reuse | new `WorldBookSourceTests.swift` | `arch/modules/background/sources.md` |
| C2 | `ChatViewModel+Support.swift`, `PromptAssembler.swift`, `PromptAssemblyModels.swift` if trace/id model changes | `PromptAssemblerTests.swift`, `ChatViewModelPromptAssemblyTests.swift` | `arch/modules/prompt-assembly.md`, `.github/instructions/prompt-engine.instructions.md` |
| D1/D2 | `WorldBookEditorViewModel.swift`, `WorldBookEditorView.swift`, `WorldBookImportView.swift`, `DatabaseManager+Content.swift` | focused DB/ViewModel tests where feasible | `arch/modules/world-book.md` |
| D3 | `DatabaseManager.swift`, `DatabaseManager+Content.swift` | delete/erase tests | `arch/data-model.md`, `arch/AntiEntropy/triangle-consistency.md` |
| Closeout | docs only | full suite evidence | `harness/<date>/world-book-vectorization/index.md`, `evidence.txt` |

## Dependency Injection

新增 Core service 不应在 View 中自行创建。

建议在 `DependencyContainer` 中持有：

```swift
let embeddingService: any EmbeddingProvider
let worldBookVectorStore: WorldBookVectorStore
let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer
let worldBookSource: WorldBookSource
```

Memory 与 WorldBook 可以共享同一个 `EmbeddingService` 实例，避免重复 lazy-load CoreML model/tokenizer。

测试中用 fixed/failing embedding provider，不加载真实 CoreML。

## 约束

- 不修改签名配置，不运行会改签名的 Xcode GUI 操作。
- migration 只追加 v15/v16，不修改 v1-v14。
- migration 中不引用 runtime Record / enum / service 常量。
- sqlite-vec virtual table 的必要 SQL 允许沿用现有 `VectorStore` 风格；普通表 CRUD 使用 GRDB Record。
- `PromptAssembler` 继续纯函数；DB、embedding、KNN 都在调用方或 Core/WorldBook source 完成。
- UI 新增文案必须写入 `OpenChat/Resources/Localizable.xcstrings`。
- 若新增 manual rebuild UI，必须显示 running/success/failure 状态，不使用 `try?` 静默失败。
