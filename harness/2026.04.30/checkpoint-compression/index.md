# Checkpoint Compression Harness

> 日期：2026-04-30
> 范围：Codex 风格持久化 compression checkpoint

## 结论

本轮已把 OpenChat 的 `.compression` context strategy 从“每轮临时摘要”改成持久化 checkpoint 语义：

- 超过阈值时压缩一次并保存 `conversation_compression_checkpoint`。
- 后续请求复用有效 checkpoint，并只拼接 checkpoint 后的 message history。
- 历史编辑/删除会删除受影响 checkpoint，避免 stale summary。
- 压缩失败 fallback 到 truncation，不保存半成品。

## 三边状态

| 边 | 状态 | 证据 |
|---|---|---|
| arch-src | 一致 | `arch/data-model.md`、`arch/modules/context-manager.md`、`.github/instructions/context-manager.instructions.md` 已写回 schema、阈值、复用、失效和 fallback 行为 |
| arch-test | 一致 | migration/database/context/chat 测试覆盖 v11 表、checkpoint CRUD、policy、hash、summarizer、compactor、reuse 和 invalidation |
| src-test | 通过 | focused suites 和 full `xcodebuild test` 均通过；full suite 为 187 tests / 41 suites |

## 传播链路

`ChatViewModel+Support.generateResponse -> PromptAssembler.preview -> ContextManager.prepareContextHistory -> CheckpointCompactor -> DatabaseManager+CompressionCheckpoints / CompressionSummarizer(APIClient) -> PreparedHistory.messagesForLegacyPrompt -> PromptAssembler.assemble`

## 验证

- Context focused suite：14 tests / 6 suites passed，`** TEST SUCCEEDED **`。
- Database focused suite：24 tests / 2 suites passed，`** TEST SUCCEEDED **`。
- Chat/prompt focused suite：16 tests / 2 suites passed，`** TEST SUCCEEDED **`。
- Full suite：187 tests / 41 suites passed，`** TEST SUCCEEDED **`。

## 关联文件

- `arch/AntiEntropy/propagation-audit.md#2026-04-30-checkpoint-compression-incremental-audit`
- `arch/AntiEntropy/triangle-consistency.md#checkpoint-compression-三边一致性写回2026-04-30`
- `harness/2026.04.30/checkpoint-compression/evidence.txt`
