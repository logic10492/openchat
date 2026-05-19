# OpenChat Phase 6 Director Mode Foundation 计划包

> 生成日期：2026-05-19
> 范围：顶层路线 Phase 6：Director / 导演模式 contract foundation。
> 状态：计划包整理完成，尚未实现 Director runtime、Stage runtime、Stage DB/UI 或多角色输出。

## 目标

本计划包只把 Director 模式的最小 contract 固化下来：

```text
current chat / future stage context
  -> DirectorInput
  -> DirectorPlan
       -> stageInstructions
       -> speakerPlan hints
       -> diagnostics
  -> later Stage / Prompt integration
```

Director 是舞台调度者，不是用户正在对话的角色。它可以建议场景节奏、发言顺序和冲突提示，但不能替角色写最终台词，也不能把内部分析作为 assistant message 写入聊天记录。

## 当前源码事实

已存在：

- `OpenChat/Core/AgentCore/AgentDescriptor.swift`：`AgentKind.director` raw value 已存在。
- `OpenChat/Core/AgentCore/AgentPolicy.swift`：`AgentPolicy.directorDefault(allowsLLM:)` 已存在，可选 LLM，但不开放 web search / network tools / database write。
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`：已有 director policy boundary 测试。
- `arch/modules/stage/*`：已有 Stage / Director / prompt-flow 目标架构文档。

尚未实现：

- `DirectorPlan`、`DirectorInput`、`StageInstruction`、`DirectorDiagnostics` runtime types。
- Director executor / controller。
- Stage DB schema、Stage UI、用户导演输入 UI。
- 多角色 participant 绑定、speaker metadata、多角色连续输出。
- DirectorPlan 接入当前 `ChatViewModel.generateResponse(...)` 主链路。

## 硬性边界

- 不把普通对话角色 agent 化。
- 不给普通角色回复开放 tool call。
- 不让 Director 替角色写最终台词。
- 不把 DirectorPlan 保存成 assistant message。
- 不新增 Stage DB migration，除非用户单独批准 Stage 持久化阶段。
- 不修改当前 Chat UI / InputBar UI 来实现导演输入控件。
- 不改 `PromptAssembler` 生产主链路，除非进入后续 Stage prompt integration 阶段。
- 不引入 multi-speaker parser、强制 JSON/tagged roleplay output 或 streaming parser repair。
- 不接 Exa / LibMan / web search。
- 不改签名配置。

## 计划文件

1. `00_source_baseline.md`：修改前传播审计、当前源码事实和 drift 风险。
2. `01_target_architecture.md`：Director 最小 contract、三种模式和非目标。
3. `02_dag_and_file_ownership.md`：DAG、并行窗口、文件归属、禁改面。
4. `03_phase_6a_director_contract_types.md`：Director DTO / diagnostics contract。
5. `04_phase_6b_mode_policy_boundaries.md`：`silent` / `agent` / `userControlled` mode policy。
6. `05_phase_6c_stage_instruction_prompt_boundary.md`：Stage instruction 与 prompt boundary。
7. `06_testing_acceptance.md`：focused tests、full suite、closeout 验收。
8. `07_new_thread_handoff.md`：新 thread 交接入口。

## 推荐执行顺序

```text
S0 source baseline + propagation audit
  -> 6A Director contract types
  -> 6B mode / policy boundary tests
  -> 6C stage instruction + prompt boundary contract
  -> docs / harness closeout
```

6A 只落 contract types。6B 锁定三种模式和 AgentCore policy 边界。6C 只建立 Director Instructions 将来进入 Stage prompt 的 contract，不切当前 Chat 主链路。

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
git status --short --branch
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/AgentPolicyTests'
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

- `DirectorMode` 三种模式 raw value / Codable contract 有测试。
- `DirectorPlan` 明确只是 stage control，不是 assistant message。
- `agent` mode 使用 `AgentPolicy.directorDefault(allowsLLM:)`，不开放 web / network / database write。
- `userControlled` mode 把用户导演输入建模为 `StageInstruction`，不作为普通 user-to-character 台词保存。
- docs / harness 明确 Director runtime、Stage DB/UI、多角色输出均未实现。
- `git diff --check` 通过。

## 写回要求

- Source：实施阶段只按 `02_dag_and_file_ownership.md` 的 ownership 改。
- Docs：同步 `arch/modules/stage/director.md`、`prompt-flow.md`、`migration-plan.md`、`PLANING.md`。
- Harness：实施阶段新增 `harness/<date>/director-mode-foundation/`，记录命令、结果、未完成项和 Phase 7+ 边界。
