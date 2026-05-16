# 07. 测试与验收

## Baseline

实施前先确认当前分支状态：

```bash
git status --short
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

如果 simulator 名称不可用，先运行：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## Phase 验收

| 阶段 | 必跑测试 |
|---|---|
| A | `PromptAssemblerTests` |
| B | `MemoryManagerRetrievalTests`, `DatabaseManagerMemoryTests`, `ChatViewModelPromptAssemblyTests` |
| C | `MigrationTests`, `MemoryExtractionParsingTests`, `MemoryManagerRetrievalTests`, `VectorStoreTests`, `DatabaseManagerMemoryTests` |
| D | `ResponsesAPIRequestTests`, `ResponsesAPIResponseTests`, `SSEParserTypedEventsTests`, `APIClientResponsesModeTests`, `ModelParametersAPIModeTests`, `ChatViewModelPromptAssemblyTests`, `MemoryReflectModelsTests` |
| Closeout | full suite |

## 最终 focused command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests' '-only-testing:OpenChatTests/ResponsesAPIRequestTests' '-only-testing:OpenChatTests/ResponsesAPIResponseTests' '-only-testing:OpenChatTests/SSEParserTypedEventsTests' '-only-testing:OpenChatTests/APIClientResponsesModeTests' '-only-testing:OpenChatTests/ModelParametersAPIModeTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

## Full suite

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 文档写回

每个阶段完成后，至少同步：

- `arch/modules/memory/index.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/memory/testing.md`
- `arch/AntiEntropy/problem.md`

涉及 schema：

- `arch/modules/memory/data-model.md`
- `arch/data-model.md`

涉及 extraction：

- `arch/modules/memory/extraction.md`
- `arch/modules/memory/hindsight-lite.md`

涉及 Responses API：

- `arch/modules/api-client.md`
- `arch/AntiEntropy/propagation-audit.md`

最终 closeout：

- `arch/AntiEntropy/triangle-consistency.md`
- `harness/<date>/memory-hindsight-lite-repair/index.md`
- 对应 `evidence.txt`，记录 focused / full suite 命令与结果。

## 完成定义

- P1 ordering 在 source、test、AE 三边均标记 Closed。
- P2 fallback 不再只有 recent-by-time；trace 可以解释本轮候选、fallback 和 selected ids。
- P2 retain v2 能保存 provenance；旧 memory 无 provenance 时不破坏检索和 UI。
- extraction prompt v2 有 source boundary 和 dedupe 约束，parser 兼容 v1。
- Responses API folding 有测试和 arch 说明，不再作为未解释风险留在 AE。
- 所有新增 migration 只追加，不修改 v1-v13。
- full suite 通过；若有 baseline failure，必须在 harness evidence 中明确标为非本轮回归。
