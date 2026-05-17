# 06. Phase 6A - BackgroundManager Integration

## 目标

新增 `BackgroundManager`，把 Phase 4 source adapters 和 Phase 5 worker 组合起来，但先不改 Prompt 输出格式。

建议新增：

```text
OpenChat/Core/Background/BackgroundManager.swift
OpenChatTests/Core/BackgroundTests/BackgroundManagerTests.swift
```

## Manager 数据流

```text
BackgroundManager.prepare(request, policy)
  -> optional pre-source stage
  -> MemoryBackgroundSource.candidates(for:)
  -> WorldBookBackgroundSource.candidates(for:)
  -> merge candidates
  -> BackgroundWorker.run(...)
  -> BackgroundPacket
```

## Source coordination 原则

- Manager 可以并发调用 source。
- Manager 不复制 Memory / WorldBook 内部排序算法。
- Manager 不直接读取 Memory / WorldBook DB。
- Manager 不把 source errors 静默吞掉；需要 diagnostics / fallback。
- 若某个 source 失败，策略可允许降级为其他 source candidates，但必须记录。

## WorldBook bounded rebuild

这是本阶段最重要的 side-effect 边界。

当前 Chat 有 bounded `rebuildMissingOrStale(worldBookId:limit:)`。如果 Phase 6 决定迁移它，只能放在 Manager 的 pre-source stage：

```text
BackgroundManager.prepare
  -> pre-source WorldBook rebuild coordinator
  -> WorldBookBackgroundSource
```

要求：

- `BackgroundWorker` 不知道 rebuild 存在。
- `WorldBookBackgroundSource` 不触发 rebuild。
- Manager tests 需要证明 rebuild closure 在 source recall 前执行。
- rebuild failure 的策略必须明确：阻断、降级 keyword-only，或记录 warning 后继续。
- 如果本阶段不迁移 rebuild，则 Chat 保留当前 side-effect，并在 harness 写明。

## API 草案

```swift
struct BackgroundManager: Sendable {
    func prepare(
        request: BackgroundRequest,
        policy: BackgroundPolicy
    ) async throws -> BackgroundPacket
}
```

依赖注入建议：

- `[any BackgroundSource]`
- `BackgroundWorker`
- optional `WorldBookPreSourceRebuilder`
- clock / requestId provider for tests

不要让 manager 自己创建 `MemoryManager`、`WorldBookSource`、`DatabaseManager` 或 `APIClient`。

## 完成定义

- Manager tests 覆盖 source 调用、candidate merge、source failure fallback、worker input、diagnostics 合并。
- 若迁移 rebuild，有独立测试证明 pre-source ordering。
- 若不迁移 rebuild，Chat 仍保持旧逻辑，harness 明确记录。
- 仍未切 Prompt / Chat，除非进入 6B/6C。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundSourceTests'
```

如迁移 rebuild：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

## 写回要求

- Source：`OpenChat/Core/Background/BackgroundManager.swift`、manager tests；如需要 DI 装配，等 6C。
- Docs：更新 `arch/modules/background/architecture.md`、`sources.md`、`migration-plan.md`。
- Harness：明确 Manager 是否接管 bounded worldBook rebuild；如接管，记录测试证据；如未接管，记录仍由 Chat 兼容链路负责。
