# 10. New Thread Handoff

## 新 thread 入口

你要执行的是 OpenChat Background Phase 5/6。先读本计划包，再读当前 source。不要从旧 Phase 4 包继续猜。

工作目录：

```text
/Volumes/SN550-Work/workspace/openchat
```

计划包：

```text
docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/
```

## 第一件事

运行：

```bash
git status --short
```

然后读取：

- `AGENTS.md`
- 本计划包 `README.md` 到 `10_new_thread_handoff.md`
- `OpenChat/Core/Background/BackgroundSourceTool.swift`
- `OpenChat/Core/Background/MemoryBackgroundSource.swift`
- `OpenChat/Core/Background/WorldBookBackgroundSource.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
- `OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`

## 执行边界

如果用户只要求 Phase 5：

- 只实现 DTO、deterministic worker、diagnostics 和 tests。
- 不碰 Chat / Prompt / DI。
- 不迁移 worldBook rebuild。

如果用户要求 Phase 6：

- 先确认 Phase 5 已通过 focused tests。
- 先做 `BackgroundManager`。
- 再做 Prompt packet compatible switch。
- 最后做 Chat switch。

## 当前重要事实

- Phase 4A-4D 已完成：source tool contract、MemoryRecallTool、WorldBookRecallTool、MemoryBackgroundSource、WorldBookBackgroundSource。
- `BackgroundWorker`、`BackgroundPacket`、`BackgroundManager`、`BackgroundAssembler` 尚未实现。
- 当前 Chat 主链路仍直接 recall memory / worldBook，并由 PromptAssembler 输出 `[Memories]` / `[World Book Entries]`。
- 当前 Chat bounded worldBook rebuild side-effect 不是 worker 行为。

## 失败时怎么处理

- 如果 tests 暴露 baseline failure，记录到 harness，不要用削弱测试来“修绿”。
- 如果需要扩大到 DB migration、签名配置、LLM selector、LibMan、Exa、统一 `[Background]` 默认输出，停止并请求用户确认。
- 如果 generator 引起无关 Xcode project drift，停止审计，不手工改签名。

## 完成定义

- 执行者能从本文件直接恢复上下文。
- Phase 5/6 的顺序、边界、测试、写回面足够明确。
- 没有把计划状态误写成已实现。

## 测试命令

开始前 baseline：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结束前 closeout 按 `09_testing_acceptance.md` 执行。

## 写回要求

- Source：按 `02_dag_and_file_ownership.md` 的阶段归属改。
- Docs：每阶段完成后写回 arch 当前事实，不写 planned as implemented。
- Harness：每阶段更新 `harness/<date>/background-worker-prompt-switch/`，至少包含完成部分、实现证据、未完成部分、未完成原因、测试结果。
