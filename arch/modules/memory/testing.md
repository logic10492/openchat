# Memory 测试与验证

## 1. 验证入口

OpenChat 是 Xcode project，不是 Swift Package。验证应使用：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=<available simulator>'
```

不要用 `swift test` 作为本仓库验证入口。

## 2. 主要测试文件

| 测试文件 | 覆盖点 |
|---|---|
| `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` | `memory_entry` / `memory_embedding` migration，`lastExtractedSortOrder` migration |
| `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift` | memory CRUD、count、ids、type、recent、conversation 查询 |
| `OpenChatTests/Core/MemoryExtractionParsingTests.swift` | `ExtractedMemory` JSON 容错、type/importance fallback |
| `OpenChatTests/Core/MemoryTests/EmbeddingServiceTests.swift` | bundle 资源、tokenizer 固定长度、384 维向量 |
| `OpenChatTests/Core/MemoryTests/VectorStoreTests.swift` | memory/vector 原子写入、批量回滚、角色隔离、删除同步、维度校验 |
| `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift` | 检索异常 fallback、提取失败不留下半索引记忆 |
| `OpenChatTests/Core/MemoryTests/MemoryExtractionCutoffTests.swift` | sortOrder cutoff、首次提取、消息不足跳过、并发消息不跳过 |
| `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` | `[Memories]` 注入、token budget、四层顺序、memory trim 保持 retrieval order |
| `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` | Chat 发送链路中的提取、检索 fallback、request 顺序和当前输入去重 |
| `OpenChatTests/Features/ChatTests/MemoryExtractionPhaseTests.swift` | Chat 提取状态模型 |

## 3. 关键回归断言

必须保持的行为：

- 自动提取使用 `conversation.lastExtractedSortOrder`，不是 `memory_entry.createdAt`。
- ViewModel 重建后仍按 DB 中的 sortOrder boundary 触发提取。
- 提取成功后更新 `lastExtractedSortOrder`。
- 消息不足时不调用提取 API，不推进 boundary。
- embedding/vector 任一失败时不留下半索引记忆。
- `VectorStore.insert(entries:)` 同批失败应回滚整批。
- 语义检索失败时 fallback 到近期记忆。
- Chat 组装 request 时当前用户输入只出现一次。
- `[Memories]` 位于 Current-Turn Context，不应进入 Stable Identity 或历史压缩 checkpoint。
- `PromptAssembler.trim(memories:)` 必须保持调用方传入的 retrieval order；即使后续记忆 importance 更高，也不能在 prompt 裁剪前重排。

## 4. 当前测试缺口

- 尚无 `MemoryRecallResult` / fallback tier / recall trace 测试，因为该功能未实现。
- 尚无 Hindsight-lite provenance schema、dedupe 或 reflect observation 行为测试，因为该功能未实现。
- 检索 telemetry / UI 可观测性没有测试，因为当前没有产品接口。
- MemoryListView 的 importance progress 尺度风险未被 UI 测试覆盖。

## 5. Hindsight-lite 目标测试

| 阶段 | 测试目标 |
|---|---|
| Phase A | 已覆盖：`PromptAssembler.trim(memories:)` 保持输入 retrieval order，不按 importance 重排 |
| Phase B | `MemoryRecallResult` 能记录 semantic/keyword/recent candidates、selected ids、omitted 和 fallback reason |
| Phase C | semantic 不可用、semantic 低相关、empty index 三类 fallback 行为不同 |
| Phase D | retain v2 解析 source range / confidence / tags / action，并兼容 v1 JSON |
| Phase E | provenance migration 不破坏旧 `memory_entry` 检索和管理 UI |
| Phase F | reflect observation 必须带 `basedOn`，不能无来源写入 |
| Phase G | Responses API system folding 后当前 `[Memories]` block 不丢失；Background block 留给后续独立计划 |

## 6. 最近验证基线

2026-05-14 Phase A focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests'
```

结果：14 tests / 1 suite passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：35 tests / 4 suites passed，`** TEST SUCCEEDED **`。Baseline 同一 focused suite 在修改前为 34 tests / 4 suites passed。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：219 tests / 45 suites passed，`** TEST SUCCEEDED **`。

若后续修改 Memory recall / fallback / provenance / Responses API request shape，应重新运行对应 focused tests 和 full suite。
