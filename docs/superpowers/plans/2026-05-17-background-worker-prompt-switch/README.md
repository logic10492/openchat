# OpenChat Background Worker / Prompt Switch 计划包

> 生成日期：2026-05-17
> 范围：Background Phase 5/6 计划，不实现源码。
> 状态：计划中。Phase 4A-4D source tools / adapters 已完成；Phase 5/6 尚未实现。

## 目标

本计划包把 Background 后续工作拆成两个硬边界阶段：

```text
Phase 5: DTO + deterministic BackgroundWorker + diagnostics
  -> 不接 Chat / Prompt
  -> 不读写 Memory / WorldBook DB
  -> 不触发 WorldBook rebuild

Phase 6: BackgroundManager + PromptAssembler compatible packet switch + Chat switch
  -> 才允许触碰 DependencyContainer / ChatViewModel+Support / PromptAssembler
  -> 先保持 [Memories] / [World Book Entries] 兼容输出
  -> [Background] 统一 block 只作为后续可选迁移
```

Phase 5 的第一段只处理 `Core/Background` 内的业务 DTO、deterministic worker 和 diagnostics。它必须在没有 Chat / Prompt runtime 接入的情况下可测试、可审计、可回滚。

## 硬性边界

- 不要把 Phase 5/6 写成已实现。
- 不要在 Phase 5 修改 `ChatViewModel+Support.swift`、`PromptAssembler.swift`、`DependencyContainer.swift`。
- Phase 6 才允许计划触碰 `OpenChat/App/DependencyContainer.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`、`OpenChat/Core/PromptEngine/PromptAssembler.swift`。
- `BackgroundWorker` 不联网、不调用 LLM、不写 DB、不生成 assistant message。
- `BackgroundWorker` 不触发 WorldBook rebuild，也不直接读写 Memory / WorldBook DB。
- `BackgroundWorker` 只能消费 Phase 4 adapter 产出的 `BackgroundCandidate`。
- Prompt 迁移先保持 `[Memories]` / `[World Book Entries]` 输出格式，来源切换为 `BackgroundPacket`。
- 统一 `[Background]` block 是 Phase 6 之后的可选迁移，不是本包默认完成条件。
- 当前 Chat bounded worldBook rebuild side-effect 不属于 worker；如迁移，只能进入 `BackgroundManager` pre-source stage，并需要单独测试。

## 计划文件

1. `00_source_baseline.md`：当前事实、必须读取文件和 drift 风险。
2. `01_target_architecture.md`：目标架构、Phase 5/6 数据流和边界。
3. `02_dag_and_file_ownership.md`：DAG、并行窗口、文件归属、禁改面。
4. `03_phase_5a_dto_contract.md`：DTO contract。
5. `04_phase_5b_deterministic_worker.md`：确定性 worker。
6. `05_phase_5c_diagnostics_tests.md`：diagnostics 与测试。
7. `06_phase_6a_background_manager_integration.md`：BackgroundManager integration。
8. `07_phase_6b_prompt_packet_compat_switch.md`：Prompt packet 兼容切换。
9. `08_phase_6c_chat_switch.md`：Chat switch。
10. `09_testing_acceptance.md`：整体验收、命令和 closeout。
11. `10_new_thread_handoff.md`：新 thread 交接入口。

## 推荐执行顺序

```text
S0 baseline read + drift audit
  -> 5A Background DTO contract
  -> 5B deterministic BackgroundWorker
  -> 5C diagnostics + focused tests
  -> Phase 5 closeout
  -> 6A BackgroundManager integration
  -> 6B PromptAssembler compatible packet switch
  -> 6C ChatViewModel switch
  -> Phase 6 closeout + arch/harness writeback
```

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
git status --short
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

如果 simulator 名称不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

新增 Swift 文件后，如果 Xcode target membership 未更新：

```bash
ruby scripts/generate_xcodeproj.rb
```

不得手工修改签名配置；`PRODUCT_BUNDLE_IDENTIFIER`、`DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE` 必须继续由 `scripts/generate_xcodeproj.rb` 管理。

## 完成定义

- 本目录下计划文件完整存在，且都明确 source / test / doc / harness 写回要求。
- Phase 5 与 Phase 6 的文件归属、禁改面、测试命令和 rollback 边界清楚。
- 文档没有把 `BackgroundWorker`、`BackgroundPacket`、`BackgroundManager`、Prompt switch 写成当前已实现。
- 世界书 bounded rebuild side-effect 被明确排除在 worker 外。

## 测试命令

计划包本身不运行产品测试；执行计划时按 `09_testing_acceptance.md` 分阶段运行 focused tests 和 full suite。

## 写回要求

- Source：本计划包创建阶段不改 source。
- Docs：只写本目录；实施阶段再按每阶段要求写回 `arch/modules/background/*`、相关 memory/world-book/prompt/chat 文档。
- Harness：实施阶段需要新增或更新 `harness/<date>/background-worker-prompt-switch/`，记录命令、结果、未完成项和 side-effect 边界。
