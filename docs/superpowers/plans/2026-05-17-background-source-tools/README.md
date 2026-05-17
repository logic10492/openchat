# OpenChat Background Source Tools 开发计划包

> 生成日期：2026-05-17
> 范围：先暴露 Memory / WorldBook read-only source tools 和 BackgroundSource adapter 准备层，再开始 Background DTO / deterministic BackgroundWorker。该计划包用于新 thread 直接执行。
> 状态：Phase 4A-4D 已实施并完成 closeout；Phase 5/6 仍为后续计划，尚未实施。

## 核心结论

Phase 4A-4D 已按“先完成工具开发，再开始后台员工 agent / BackgroundWorker 开发”的顺序落地。

当前已完成前置项：

- Memory recall ordering 已有 `MemoryRecallResult` / trace，可被 source tool 包装。
- 世界书向量化已完成，`WorldBookSource.recallEntries(...)` 已产出 keyword + semantic result / trace。
- AgentCore foundation 已完成，`AgentPolicy.backgroundWorkerDefault()` 和 deterministic executor 权限拒绝已有测试覆盖。

已建立内部 read-only 工具边界：

```text
MemoryManager.recallMemories(...)
  -> MemoryRecallTool
  -> MemoryBackgroundSource
  -> BackgroundCandidate

WorldBookSource.recallEntries(...)
  -> WorldBookRecallTool
  -> WorldBookBackgroundSource
  -> BackgroundCandidate
```

工具和 adapter 已稳定；后续才进入：

```text
Core/Background DTO
  -> deterministic BackgroundWorker
  -> BackgroundPacket
  -> BackgroundAssembler
  -> Chat / Prompt switch
```

## 范围边界

本计划包分两段：

1. 必做的工具优先段：Phase 4A 到 Phase 4D。
2. 工具完成后的 worker 后置段：Phase 5 到 Phase 6，只能在 source tools 和 adapter 验收后开始。

纳入本计划包：

- 新增内部 read-only source tool contract。
- 新增 `MemoryRecallTool`，只包装 `MemoryManager.recallMemories(...)`。
- 新增 `WorldBookRecallTool`，只包装 `WorldBookSource.recallEntries(...)`。
- 新增或准备 `MemoryBackgroundSource` / `WorldBookBackgroundSource`，只把 tool result 转成 `BackgroundCandidate`。
- 定义后续 `Core/Background` DTO、deterministic worker、prompt switch 的实施顺序、文件归属和验收标准。
- 同步更新相关 arch 文档和 harness evidence。

不纳入工具优先段：

- 不实现 BackgroundWorker。
- 不切 Chat prompt。
- 不改 `[Memories]` / `[World Book Entries]` 兼容输出。
- 不引入 LLM-assisted selector。
- 不引入 LibMan、Exa、synthesis。
- 不新增数据库 migration。

## 必须避免的提前事项

这些是硬性 non-goals，执行计划时必须写入每个阶段的 review checklist：

- 不要在 Phase 4 改 prompt 注入。
- 不要让 BackgroundWorker 直接调用 DB、MemoryManager raw internals 或 WorldBook raw internals。
- 不要在工具层复制 Memory / WorldBook 排序算法。
- 不要把 LibMan、Exa、synthesis 混入每轮 background worker。
- 不要让世界书 rebuild 成为 BackgroundWorker side effect。

对应解释：

- Phase 4 只做 source tool 和 adapter-readiness；Chat 主链路仍由当前 Memory / WorldBook 兼容注入承担。
- BackgroundWorker 后续只能消费 `BackgroundCandidate`，不能绕过 source tool 直接碰 Memory / WorldBook 内部实现。
- Memory semantic/keyword/recent fusion 和 WorldBook keyword+semantic fusion 继续由各 source 拥有，tool 层只透传 result / trace。
- LibMan 是素材构建 agent，Exa 是素材检索能力，synthesis 是低频 observation/reflect 能力；它们都不是每轮 BackgroundWorker 默认路径。
- 世界书 embedding rebuild 属于 WorldBook lifecycle / current compatible chat path 的 side-effect boundary；BackgroundWorker 不触发 rebuild。

## 阅读顺序

1. `00_source_baseline.md`：当前 source/doc 基线与实施前必须读的文件。
2. `01_target_architecture.md`：目标边界、工具层、adapter、worker 后置关系。
3. `02_dag_and_file_ownership.md`：阶段 DAG、允许文件和禁止文件。
4. `03_phase_4a_tool_contract.md`：内部 read-only tool contract。
5. `04_phase_4b_memory_recall_tool.md`：MemoryRecallTool 计划。
6. `05_phase_4c_world_book_recall_tool.md`：WorldBookRecallTool 计划。
7. `06_phase_4d_background_source_adapters.md`：adapter-readiness 计划。
8. `07_phase_5_6_worker_prompt_switch.md`：工具完成后的 worker 和 prompt 切换计划。
9. `08_testing_acceptance.md`：测试、文档写回、完成定义。
10. `09_new_thread_handoff.md`：新 thread 执行入口和硬性边界。

## 推荐执行顺序

```text
S0 baseline read + propagation audit
  -> 4A source tool contract
  -> 4B MemoryRecallTool + tests
  -> 4C WorldBookRecallTool + tests
  -> 4D BackgroundSource adapter + tests
  -> Lead closeout for tool package
  -> Phase 5 Background DTO + deterministic worker
  -> Phase 6 Prompt switch to BackgroundPacket
```

Phase 5/6 不能和 Phase 4 并行落地；最多可以提前写草案文档，不能提前改 runtime。

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
git status --short
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

如果 simulator 名称不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

新增 Swift 文件后，如 Xcode target 未包含，应运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

该脚本会重建 `OpenChat.xcodeproj`。签名配置必须继续来自脚本，不得手工修改 `PRODUCT_BUNDLE_IDENTIFIER`、`DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE`。
