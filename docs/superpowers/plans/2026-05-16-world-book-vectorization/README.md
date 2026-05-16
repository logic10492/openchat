# OpenChat 世界书向量化改造计划包

> 生成日期：2026-05-16
> 范围：世界书条目的 embedding schema、向量索引、keyword + semantic 召回、现有世界书重建、CRUD / import / delete 维护，以及第一阶段 Prompt 输出兼容。
> 状态：Phase A/B/C/D 已实施并通过 focused tests；full-suite closeout 见本文件与 `harness/2026.05.16/world-book-vectorization/evidence.txt`。

## 范围边界

本计划只落地世界书向量化的最小闭环：

- 追加 `world_book_entry_embedding` sqlite-vec virtual table。
- 追加 `world_book_entry_embedding_meta` 普通表，用于审计、增量重建和已导入世界书 backfill。
- 新增 `Core/WorldBook` 管理层：`WorldBookVectorStore`、`WorldBookEmbeddingIndexer`、`WorldBookRecallModels`、`WorldBookSource`。
- 让 WorldBook source 同时产出 keyword candidates 与 semantic candidates。
- CRUD / import / delete 世界书条目时同步维护或标记重建 embedding。
- 支持把当前数据库里已经导入的 `world_book_entry` 全量或增量向量化。
- 保持第一阶段 Prompt 输出兼容：仍输出 `[World Book Entries]` block，不提前切到 `BackgroundWorker` / `BackgroundPacket`。

不纳入本计划：

- 不实现 `Core/Background`、`BackgroundWorker`、`BackgroundPacket`。
- 不把 Memory 与 WorldBook 合并成统一调度层；本计划只让 WorldBook source 输出未来可接入 Background 的 candidate/trace 形态。
- 不改变角色卡 Stable Identity、ContextManager 历史压缩、Memory retain/recall 的现有契约。
- 不把 embedding backfill 写进 migration；CoreML embedding 必须在 runtime indexer 中执行，migration 只负责 schema。

## 当前源码基线

已存在且应复用：

- `OpenChat/Core/Memory/EmbeddingService.swift`：MultilingualE5Small CoreML embedding，384 维，E5 query/passage prefix。
- `OpenChat/Core/Memory/VectorStore.swift`：sqlite-vec virtual table 的插入、搜索、删除样式。
- `OpenChat/Core/Database/Migrations.swift`：Phase A 后当前最新 migration 是 `v16_create_world_book_entry_embedding_meta`；v15/v16 已按本计划追加。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：当前会把触发到的世界书条目注入 `[World Book Entries]`。
- `OpenChat/Features/WorldBook/ViewModels/WorldBookEditorViewModel.swift` 与 `WorldBookEditorView.swift`：世界书 CRUD / Markdown import 入口。
- `OpenChat/Core/Database/DatabaseManager+Content.swift`：世界书保存/批量导入/删除主链路已在 Phase D 接入 embedding/meta 维护；sqlite-vec virtual table 清理不依赖 FK cascade。

Phase A 已落地：

- `OpenChat/Core/Database/Migrations.swift`：`v15_create_world_book_entry_embedding`、`v16_create_world_book_entry_embedding_meta`。
- `OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`。
- `OpenChat/Core/WorldBook/WorldBookError.swift`、`WorldBookRecallModels.swift`、`WorldBookVectorStore.swift`。
- `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift`。

Phase B 已落地：

- `OpenChat/Core/WorldBook/WorldBookEmbeddingTextBuilder.swift`。
- `OpenChat/Core/WorldBook/WorldBookEntryHasher.swift`。
- `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`。
- `OpenChat/App/DependencyContainer.swift`：Memory 与 WorldBook 共用同一个 `EmbeddingService`。
- `OpenChat/Core/Memory/EmbeddingService.swift`：新增 `embeddingModelId` 作为 hash/meta 审计输入。
- `OpenChatTests/Core/WorldBookTests/WorldBookEmbeddingTextBuilderTests.swift`。
- `OpenChatTests/Core/WorldBookTests/WorldBookEntryHasherTests.swift`。
- `OpenChatTests/Core/WorldBookTests/WorldBookEmbeddingIndexerTests.swift`。

当前缺口：

- `world_book_entry` 已有 embedding / meta 表；缺口已由 Phase A 关闭。
- 已导入世界书已有 Core backfill / rebuild 入口；缺口已由 Phase B 关闭。
- Prompt 侧世界书召回只有 keyword trigger 的缺口已由 Phase C 关闭。
- 世界书删除和 `eraseAllData(...)` 的 sqlite-vec/meta 显式清理缺口已由 Phase D 关闭。
- `BackgroundWorker` / `BackgroundPacket` 统一调度仍不在本计划当前实现范围内。

## Phase A 验证记录

Baseline（实施前）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：62 tests / 4 suites passed，`** TEST SUCCEEDED **`。

Phase A focused（实施后）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests'
```

结果：39 tests / 2 suites passed，`** TEST SUCCEEDED **`。

Phase A broader focused（实施后，防 src 漂移）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：72 tests / 5 suites passed，`** TEST SUCCEEDED **`。

Full suite（实施后）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'
```

实际设备：iOS 26.5 `iPhone 17`。结果：261 tests / 47 suites passed，`** TEST SUCCEEDED **`。

备注：同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后 full suite 通过。

## Phase B 验证记录

Phase B focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests'
```

结果：12 tests / 3 suites passed，`** TEST SUCCEEDED **`。

Phase B broader focused（防 src 漂移）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：84 tests / 8 suites passed，`** TEST SUCCEEDED **`。

Full suite（Phase B 后）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'
```

实际设备：iOS 26.5 `iPhone 17`。结果：273 tests / 50 suites passed，`** TEST SUCCEEDED **`。

备注：同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后 full suite 通过。

## Phase C 验证记录

Baseline（实施前，沿用计划基线命令）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：67 tests / 4 suites passed，`** TEST SUCCEEDED **`。

Phase C focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：34 tests / 3 suites passed，`** TEST SUCCEEDED **`。

Phase A/B/C broader focused（防 src 漂移）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：92 tests / 9 suites passed，`** TEST SUCCEEDED **`。

Full suite（Phase C 后）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

实际设备：iOS 26.5 `iPhone 17 Pro`。结果：281 tests / 51 suites passed，`** TEST SUCCEEDED **`。

备注：同日一次 `iPhone 17 Pro` full-suite 重试在 `EmbeddingServiceTests.test_embedding_outputs_384_finite_normalized_values` 处出现一次 app bundle 内 `MultilingualE5Small.mlmodelc` runtime lookup 失败；随后单独重跑 `EmbeddingServiceTests` 4 tests / 1 suite passed，再次 full suite 通过。该失败未在后续重跑复现。

## Phase D 验证记录

Baseline（实施前，沿用计划基线命令）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：69 tests / 4 suites passed，`** TEST SUCCEEDED **`。

Phase D focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'
```

结果：9 tests / 4 suites passed，`** TEST SUCCEEDED **`。

Final A/B/C/D focused acceptance：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'
```

结果：94 tests / 12 suites passed，`** TEST SUCCEEDED **`。

Full suite（Phase D closeout）：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

实际设备：iOS 26.5 `iPhone 17 Pro`。结果：289 tests / 54 suites passed，`** TEST SUCCEEDED **`。

Closeout recheck（2026-05-16 18:54-18:58 +0800）：

- 发现并修复新建世界书界面直接添加 entry 的接线漂移：`WorldBookEditorViewModel.saveEntry(_:)` 现在会先确保 world book 已保存，并把 entry 绑定到真实 `worldBook.id` 后再保存/index。
- 补充 `WorldBookEditorViewModelTests.test_save_entry_for_new_world_book_persists_parent_and_rebinds_entry`，证明新建 world book + direct Add Entry 不会使用 draft id 或触发 FK 漂移。
- 补充 `ChatViewModelPromptAssemblyTests.test_world_book_source_semantic_failure_falls_back_to_keyword_block`，证明 Chat 主链路在 `WorldBookSource` semantic embedding 不可用时仍 fallback 到 keyword candidate，并保持单个 `[World Book Entries]` block。
- 近改动 focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：19 tests / 2 suites passed，`** TEST SUCCEEDED **`。

- iOS 26.5 `iPhone 17 Pro` final focused acceptance 在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用 iOS 26.5 `iPhone 17` (`2277CB75-AF36-4ABF-84EE-7444C1DD6759`) 后通过：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'
```

结果：96 tests / 12 suites passed，`** TEST SUCCEEDED **`。

- iOS 26.5 `iPhone 17` full suite 随后同样在测试体执行前遇到 Simulator `Busy ("Application failed preflight checks")`；换用 iOS 26.5 `iPhone 17 Pro Max` (`B20ADF19-7ADC-427D-9EBE-A76712A3E2AE`) 后通过：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=B20ADF19-7ADC-427D-9EBE-A76712A3E2AE'
```

结果：291 tests / 54 suites passed，`** TEST SUCCEEDED **`。

## 阅读顺序

1. `00_gap_matrix.md`：source / arch / test 缺口矩阵。
2. `01_target_architecture.md`：目标模块、schema、数据流、兼容策略。
3. `02_dag_and_file_ownership.md`：阶段 DAG、并行边界、文件归属。
4. `03_phase_a_schema_vector_store.md`：migration、record、vector store。
5. `04_phase_b_indexer_backfill.md`：embedding text、hash、增量/全量重建。
6. `05_phase_c_world_book_source_prompt_compat.md`：keyword + semantic candidates、Prompt 输出兼容。
7. `06_phase_d_crud_import_delete_wiring.md`：CRUD/import/delete/eraseAllData 维护。
8. `07_testing_acceptance.md`：focused tests、full suite、文档和 harness closeout。

## 推荐执行顺序

```text
S0 baseline source read + current focused tests
  -> A schema + vector store
  -> B indexer + existing world-book backfill
  -> C WorldBookSource + PromptAssembler compatible input path
  -> D CRUD / import / delete / eraseAllData wiring
  -> Lead closeout: docs + harness evidence + full suite
```

Phase A/B 可以先不改 Chat 链路，只证明已有世界书能被向量化并可 KNN 查询。Phase C 才把 semantic candidates 放入当前 prompt path。Phase D 必须关闭维护一致性，否则后续会出现 `world_book_entry` 与 embedding/meta 半同步。

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
git status --short
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

如 simulator 名称不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

所有验证记录必须写明实际 simulator 名称、命令和结果。
