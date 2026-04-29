# Memory Vector Reliability Repair Result

> 日期：2026-04-30
> 范围：OpenChat Memory embedding/vector/retrieval reliability

## 修复摘要

- 模型与 tokenizer 资源进入 App Bundle，并由 `scripts/generate_xcodeproj.rb` 保持。
- `EmbeddingService` 使用固定 256 CoreML 输入、Unigram tokenizer、Float16 / Float32 输出读取和 384 维归一化校验。
- `VectorStore` 原子保存 `memory_entry + memory_embedding`，并用 sqlite-vec KNN 查询验证角色隔离。
- `MemoryManager` 检索失败 fallback 到近期记忆，Chat 不再用 `try?` 静默吞掉全部记忆。

## 三边一致性

| 边 | 结论 | 证据 |
|---|---|---|
| arch-src | 一致 | `arch/modules/memory/index.md` 与 `OpenChat/Core/Memory/*` 同步描述资源、embedding、vector、fallback 行为 |
| arch-test | 一致 | 本轮 memory vector reliability 由 `EmbeddingServiceTests`、`VectorStoreTests`、`MemoryManagerRetrievalTests`、`ChatViewModelPromptAssemblyTests` 覆盖；不声明周期阈值 / `ChatView.onDisappear` 自动触发路径已有端到端测试 |
| src-test | 一致 | Focused memory/prompt suite 27 tests 通过；full `xcodebuild test` 166 tests / 34 suites 通过 |

## Propagation Audit

- Evidence file: `harness/2026.04.30/memory-vector-reliability/evidence.txt`
- Arch writeback: `arch/AntiEntropy/propagation-audit.md`
- 结论：影响面集中在 `Core/Memory` 与 Chat 发送链路的 memory retrieval 错误处理，未新增 Feature 间直接依赖。

## Verification Commands

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/EmbeddingServiceTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/PromptAssemblerTests'
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Verification Transcript Excerpts

Focused memory/prompt run (`/tmp/openchat-memory-focused.log`):

```text
✔ Test test_insert_batch_rolls_back_all_memories_when_later_vector_insert_fails() passed
✔ Test test_extractMemories_rolls_back_batch_when_later_embedding_is_invalid() passed
✔ Test run with 27 tests in 5 suites passed after 1.381 seconds.
** TEST SUCCEEDED **
```

Full suite run (`/tmp/openchat-memory-full.log`):

```text
✔ Test test_insert_batch_rolls_back_all_memories_when_later_vector_insert_fails() passed
✔ Test test_extractMemories_rolls_back_batch_when_later_embedding_is_invalid() passed
✔ Test test_sendMessage_includes_recent_memory_when_semantic_retrieval_fails() passed
✔ Test run with 166 tests in 34 suites passed after 1.246 seconds.
** TEST SUCCEEDED **
```
