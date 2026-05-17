# 01. Target Architecture

## 目标分层

目标链路分两段落地。

工具优先段：

```text
Core/Memory
  MemoryRecallTool
    wraps MemoryManager.recallMemories(...)

Core/WorldBook
  WorldBookRecallTool
    wraps WorldBookSource.recallEntries(...)

Core/Background
  BackgroundSourceTool
  BackgroundRequest
  BackgroundCandidate
  MemoryBackgroundSource
  WorldBookBackgroundSource
```

Worker 后置段：

```text
Core/Background
  BackgroundPolicy
  BackgroundWorkerInput
  BackgroundWorker
  BackgroundPacket
  BackgroundEntry
  BackgroundOmission
  BackgroundDiagnostics
  BackgroundAssembler
  BackgroundManager
```

## 工具层职责

`MemoryRecallTool` / `WorldBookRecallTool` 只做：

- 接收结构化 input。
- 调用现有 source recall API。
- 返回现有 result / trace。
- 附带 tool-level diagnostics，例如 startedAt / duration / source type / input size。

工具层不做：

- 不做最终排序。
- 不做跨 source fusion。
- 不复制 Memory / WorldBook 内部 rank fusion。
- 不裁剪 prompt token budget。
- 不生成 prompt text。
- 不写数据库。
- 不联网。
- 不触发 rebuild。

## Adapter 职责

`MemoryBackgroundSource` / `WorldBookBackgroundSource` 只做结构转换：

```text
MemoryRecallResult.entries
  -> BackgroundCandidate(sourceType: .memory, ...)

WorldBookRecallResult.entries
  -> BackgroundCandidate(sourceType: .worldBook, ...)
```

adapter 可以把 trace 写进 metadata，供后续 diagnostics 使用。

adapter 不做：

- 不跨 source 排序。
- 不 budget 裁剪。
- 不合并重复 facts。
- 不改写 content。
- 不生成用户可见文本。

## BackgroundWorker 职责

BackgroundWorker 后续只处理 adapter 产出的 candidates：

- 排序候选。
- 去重或合并高度重复条目。
- 标记冲突或低置信条目。
- 根据 token budget 裁剪。
- 返回 omission diagnostics。

第一版只允许 deterministic worker：

- 不调用 LLM。
- 不联网。
- 不写数据库。
- 不生成 assistant message。
- 复用 `AgentPolicy.backgroundWorkerDefault()`。

## Prompt 切换原则

Prompt 切换只能在 tool + adapter + deterministic worker 都完成并有测试后开始。

第一步可以保持文本格式兼容：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

但来源改成 `BackgroundPacket`。

第二步再考虑统一：

```text
[Background]
[World]
...

[Memory]
...
[/Background]
```

调度权必须先统一到 packet，文本格式不能反过来决定调度策略。

## 硬性禁止事项

- 不要在 Phase 4 改 prompt 注入。
- 不要让 BackgroundWorker 直接调用 DB、MemoryManager raw internals 或 WorldBook raw internals。
- 不要在工具层复制 Memory / WorldBook 排序算法。
- 不要把 LibMan、Exa、synthesis 混入每轮 background worker。
- 不要让世界书 rebuild 成为 BackgroundWorker side effect。
