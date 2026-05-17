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

## 本修订的默认执行决策

Phase 6A 只落 `BackgroundManager` 本体和 tests；不装配 DI，不切 Chat，不改 Prompt。Manager 接收调用方传入的 `BackgroundPolicy`，不自己根据 endpoint 或 PromptAssembler 计算 token budget。

`BackgroundPolicy.tokenBudget` 在 Phase 6A/6C 第一版中定义为 **candidate selection ceiling**，不是最终 prompt block budget。最终是否进入 request body 仍由 Phase 6B 的 packet-aware PromptAssembler preview 负责按现有 `TokenBudget` 裁剪。实现和 diagnostics 必须区分：

- `BackgroundPacket.entries`：worker 选出的候选集合。
- prompt included ids：PromptAssembler 最终放入 `[World Book Entries]` / `[Memories]` 的条目。

6A tests 使用显式 policy，不读取 Settings，也不依赖 endpoint。

## Source coordination 原则

- Manager 可以并发调用 source。
- Manager 不复制 Memory / WorldBook 内部排序算法。
- Manager 不直接读取 Memory / WorldBook DB。
- Manager 不把 source errors 静默吞掉；需要 diagnostics / fallback。
- 若某个 source 失败，策略可允许降级为其他 source candidates，但必须记录。

默认 fallback 策略：

- 单个 source 失败：记录 warning / source summary，继续使用其他 source candidates。
- 全部 source 失败：返回 empty packet + diagnostics，除非失败来自 worker policy denial。
- worker policy denial：抛 typed error，不返回 partial packet。
- 6A 不实现 Chat 兼容的 worldBook keyword fallback；该行为必须在 6C 切换前通过 explicit fallback source / closure 或等价 manager policy 补齐。

## WorldBook bounded rebuild

这是本阶段最重要的 side-effect 边界。

当前 Chat 有 bounded `rebuildMissingOrStale(worldBookId:limit:)`。如果 Phase 6 决定迁移它，只能放在 Manager 的 pre-source stage：

```text
BackgroundManager.prepare
  -> pre-source WorldBook rebuild coordinator
  -> WorldBookBackgroundSource
```

本修订默认路线：**Phase 6 第一版不迁移 bounded rebuild**。它继续保留在 `ChatViewModel` 当前兼容链路中，先完成 packet source switch。rebuild 迁移只能作为后续小阶段执行。

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

如果为了 6C 保持 worldBook recall failure 的旧行为，需要新增或注入 worldBook keyword fallback provider，它也必须是 manager dependency，不能在 manager 内部自行创建 DB / source / API client。

## 完成定义

- Manager tests 覆盖 source 调用、candidate merge、source failure fallback、worker input、diagnostics 合并。
- 若迁移 rebuild，有独立测试证明 pre-source ordering。
- 本修订默认不迁移 rebuild：Chat 仍保持旧逻辑，harness 明确记录。
- source failure fallback 的默认行为有 tests：partial source failure 继续，worker policy denial 不返回 partial packet。
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
