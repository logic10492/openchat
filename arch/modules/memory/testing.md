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
| `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` | `memory_entry` / `memory_embedding` migration，`lastExtractedSortOrder` migration，`memory_entry_provenance` v14 migration，`memory_entry_link` v17 migration / index / cascade |
| `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift` | memory CRUD、count、ids、type、recent、recent high-value、conversation 查询、link save/fetch/dedupe/relation validation |
| `OpenChatTests/Core/MemoryExtractionParsingTests.swift` | `ExtractedMemory` JSON 容错、type/importance fallback、v2 字段解析、provenance CRUD、旧 memory 无 provenance 兼容 |
| `OpenChatTests/Core/MemoryTests/EmbeddingServiceTests.swift` | bundle 资源、tokenizer 固定长度、384 维向量 |
| `OpenChatTests/Core/MemoryTests/VectorStoreTests.swift` | memory/vector 原子写入、entry + embedding + links 原子写入、批量回滚、角色隔离、删除同步、维度校验 |
| `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift` | `MemoryRecallResult` / trace、semantic/keyword/recent high-value fallback、兼容 retrieve API、提取失败不留下半索引记忆、v2 dedupe、越界 source range 丢弃、向量失败不留下 provenance 半成品 |
| `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift` | reflect request / observation contract、parser、executor、apply、MemoryListViewModel review state、basedOn/source ids 非空、confidence clamp、link relation 集合 |
| `OpenChatTests/Core/MemoryTests/MemoryExtractionCutoffTests.swift` | sortOrder cutoff、首次提取、消息不足跳过、并发消息不跳过 |
| `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` | `[Memories]` 注入、token budget、四层顺序、memory trim 保持 retrieval order |
| `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` | Chat 发送链路中的提取、检索 fallback、request 顺序和当前输入去重 |
| `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift` | Responses API system folding、`[Memories]` 进入 `instructions`、非 system `input` 不重复 current input |
| `OpenChatTests/Features/ChatTests/MemoryExtractionPhaseTests.swift` | Chat 提取状态模型 |

## 3. 关键回归断言

必须保持的行为：

- 自动提取使用 `conversation.lastExtractedSortOrder`，不是 `memory_entry.createdAt`。
- ViewModel 重建后仍按 DB 中的 sortOrder boundary 触发提取。
- 提取成功后更新 `lastExtractedSortOrder`。
- 消息不足时不调用提取 API，不推进 boundary。
- embedding/vector 任一失败时不留下半索引记忆，也不留下 provenance 半成品。
- `VectorStore.insert(entries:)` / `insert(entries:provenances:)` 同批失败应回滚整批。
- 语义检索失败时 fallback 到 keyword + recent high-value；不会无条件注入普通 recent 噪声。
- semantic no hit 时 keyword 优先；无 keyword 时只补 relationship / summary / high-importance recent high-value。
- `MemoryRecallTrace` 记录 semantic/keyword/recent candidate 数量、selected ids、fallback reason 和 omitted。
- Chat 组装 request 时当前用户输入只出现一次。
- `[Memories]` 位于 Current-Turn Context，不应进入 Stable Identity 或历史压缩 checkpoint。
- `PromptAssembler.trim(memories:)` 必须保持调用方传入的 retrieval order；即使后续记忆 importance 更高，也不能在 prompt 裁剪前重排。

## 4. 当前测试缺口

- 检索 / Background diagnostics 已接入 `RetrievalTraceView`，在 Chat detailed stats 下展示；尚无 XCUITest 覆盖该 UI。
- reflect 手动入口已有 ViewModel 级测试；尚无 XCUITest 自动点击 MemoryListView 的端到端 UI 流程。
- idle/background reflect draft worker 已有 `MemoryReflectBackgroundWorkerTests`；duplicate 自动删除、自动 apply/write 和冲突自动解决尚未实现，因此没有对应行为测试。

## 5. Hindsight-lite 目标测试

| 阶段 | 测试目标 |
|---|---|
| Phase A | 已覆盖：`PromptAssembler.trim(memories:)` 保持输入 retrieval order，不按 importance 重排 |
| Phase B | 已覆盖：`MemoryRecallResult` 能记录 semantic/keyword/recent candidates、selected ids、omitted 和 fallback reason |
| Phase C | 已覆盖：retain v2 解析 source range / confidence / tags / action / dedupeKey，并兼容 v1 JSON；provenance migration 不破坏旧 `memory_entry`；同批 dedupe；source range validation；atomic entry+embedding+provenance 写入 |
| Phase D | 已覆盖：reflect observation 必须带 `basedOn`；Responses API system folding 后当前 `[Memories]` block 不丢失、不进入 user message、current input 不重复 |
| Phase 5 | 已覆盖：`memory_entry_link` v17 schema/index/cascade；parser/executor request shape 和 missing/cross-character source rejection；confirmed apply 原子写 entry + embedding + links 并保留原始记忆；ViewModel run/apply/error state |

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

2026-05-14 Phase B focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：28 tests / 3 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：49 tests / 5 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：225 tests / 45 suites passed，`** TEST SUCCEEDED **`。

2026-05-14 22:49-22:52 +0800 按 B 阶段验收重新执行：

- `MemoryManagerRetrievalTests` + `DatabaseManagerMemoryTests` + `ChatViewModelPromptAssemblyTests`：28 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- 再加 `VectorStoreTests` + `PromptAssemblerTests` 的 broader focused suite：49 tests / 5 suites passed，`** TEST SUCCEEDED **`。
- Full suite：225 tests / 45 suites passed，`** TEST SUCCEEDED **`。

2026-05-15 Phase C focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests'
```

结果：107 tests / 7 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：244 tests / 45 suites passed，`** TEST SUCCEEDED **`。

2026-05-16 Phase D focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/ResponsesAPITests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

结果：旧命令 16 tests / 2 suites passed，`** TEST SUCCEEDED **`。注意 `ResponsesAPITests` 是文件名选择器，Swift Testing 未选中该文件内的 suite；该命令主要验证 Chat request shape 和 MemoryReflect contract 编译/行为。

enum raw value cleanup 后重跑 reflect contract：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=4435A025-9E0B-40AF-9BE0-DE0648F77AED' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

结果：5 tests / 1 suite passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=6F61E759-8E3C-4951-B929-0A63AA47BFBB' '-only-testing:OpenChatTests/ResponsesAPIRequestTests' '-only-testing:OpenChatTests/ResponsesAPIResponseTests' '-only-testing:OpenChatTests/SSEParserTypedEventsTests' '-only-testing:OpenChatTests/APIClientResponsesModeTests' '-only-testing:OpenChatTests/ModelParametersAPIModeTests'
```

结果：21 tests / 5 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

结果：17 tests / 2 suites passed，`** TEST SUCCEEDED **`。中间两次 focused retry 在进入测试断言前被 simulator preflight `Busy` 拒绝，按环境 runner failure 记录。

2026-05-16 Lead closeout verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=B20ADF19-7ADC-427D-9EBE-A76712A3E2AE' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests'
```

结果：15 tests / 1 suite passed，`** TEST SUCCEEDED **`。该重跑验证 `MemoryManagerRetrievalTests` 已全部使用 `InMemoryAPIKeyStore()`，避免 full suite 并发执行时测试路径触碰真实 Keychain 而出现 `-25299` duplicate item。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=4DC4D569-DFFE-41E4-9383-2A6386B5B26E'
```

结果：251 tests / 46 suites passed，`** TEST SUCCEEDED **`。

2026-05-18 Phase 5 Memory reflect focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：84 tests / 5 suites passed，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.18_01-21-54-+0800.xcresult`。

同步检查：

- `git diff --check`：PASS。
- `python3 -m json.tool OpenChat/Resources/Localizable.xcstrings >/dev/null`：PASS。
- 默认 iOS 26.5 `iPhone 17 Pro` destination full suite 在启动测试 runner 前遇到 simulator Busy：`Application failed preflight checks`。改用 alternate simulator `id=F8D0D88B-71FD-471F-855A-B2B5D8267117` 后 full suite 通过 360 tests / 66 suites，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.18_01-42-36-+0800.xcresult`。
