# 09. New Thread Handoff

## 新 thread 入口

请在新 thread 中从这个计划包开始执行：

```text
docs/superpowers/plans/2026-05-17-background-source-tools/README.md
```

执行目标：

```text
先完成 Memory / WorldBook read-only source tools 和 BackgroundSource adapters，
再开始 BackgroundWorker / BackgroundPacket / prompt switch。
```

## 新 thread 推荐开场指令

```text
请按照 docs/superpowers/plans/2026-05-17-background-source-tools/README.md 执行计划。
先完成 Phase 4A-4D：source tool contract、MemoryRecallTool、WorldBookRecallTool、BackgroundSource adapters。
执行前阅读 00_source_baseline.md 并做 propagation audit。
Phase 4 期间禁止修改 Chat prompt 注入、PromptAssembler runtime、ChatViewModel runtime switch。
完成后运行 08_testing_acceptance.md 里的 focused tests，并把实现证据写回 arch 和 harness。
不要提前执行 Phase 5/6，除非 Phase 4 已验收完成。
```

## 硬性边界

新 thread 必须遵守：

- 不要在 Phase 4 改 prompt 注入。
- 不要让 BackgroundWorker 直接调用 DB、MemoryManager raw internals 或 WorldBook raw internals。
- 不要在工具层复制 Memory / WorldBook 排序算法。
- 不要把 LibMan、Exa、synthesis 混入每轮 background worker。
- 不要让世界书 rebuild 成为 BackgroundWorker side effect。

## Phase 4 成功条件

- `MemoryRecallTool` 只包装 `MemoryManager.recallMemories(...)`。
- `WorldBookRecallTool` 只包装 `WorldBookSource.recallEntries(...)`。
- tools 输出保持原 result 顺序和 trace metadata。
- `MemoryBackgroundSource` / `WorldBookBackgroundSource` 只做 `BackgroundCandidate` 转换。
- `PromptAssembler` 和 `ChatViewModel+Support` 没有 runtime switch。
- focused tests 通过，并记录实际命令和结果。
- `arch/modules/background/*`、memory/world-book 相关 docs 和 harness evidence 已写回。

## Phase 5/6 启动门槛

只有满足 Phase 4 成功条件后，才允许进入：

```text
Core/Background DTO
  -> deterministic BackgroundWorker
  -> BackgroundPacket
  -> BackgroundAssembler
  -> Chat / Prompt switch
```

Phase 5 第一版只能是 deterministic worker，复用 `AgentPolicy.backgroundWorkerDefault()`，不调用 LLM、不联网、不写 DB、不生成 assistant message。
