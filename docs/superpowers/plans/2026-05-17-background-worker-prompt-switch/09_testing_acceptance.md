# 09. Testing Acceptance

## 分阶段测试矩阵

| 阶段 | 必跑 focused tests | 目的 |
|---|---|---|
| S0 | `MemoryRecallToolTests`、`WorldBookRecallToolTests`、`BackgroundSourceTests`、`AgentPolicyTests`、`DeterministicAgentExecutorTests` | 确认 Phase 4 / AgentCore 基线 |
| 5A | `BackgroundPacketTests`、`BackgroundSourceTests` | DTO contract 和 Phase 4 兼容 |
| 5B | `BackgroundWorkerTests`、`AgentPolicyTests`、`DeterministicAgentExecutorTests` | deterministic worker 与 policy boundary |
| 5C | `BackgroundDiagnosticsTests`、`BackgroundWorkerTests` | diagnostics 完整性 |
| 6A | `BackgroundManagerTests`、`BackgroundSourceTests`、`BackgroundWorkerTests` | manager source orchestration |
| 6B | `PromptAssemblerTests`、Background focused tests | packet compatible prompt block |
| 6C | `ChatViewModelPromptAssemblyTests`、`PromptAssemblerTests`、`BackgroundManagerTests` | 主链路 switch |

## 推荐命令

Phase 5 closeout：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

Phase 6 closeout focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Simulator fallback：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## 必须新增或更新的测试主题

Phase 5：

- DTO identity / equality / default policy。
- Worker deterministic order。
- Memory relevance 不被 importance 覆盖。
- WorldBook priority 不覆盖低相关性。
- Duplicate / budget / per-source limit omissions。
- Agent policy denial。
- Diagnostics selected / omitted / source summary。

Phase 6：

- Manager source ordering and fallback。
- Manager pre-source worldBook rebuild ordering，如迁移该 side-effect。
- Packet -> compatible `[Memories]` / `[World Book Entries]` block。
- Chat request body 使用 packet selected entries。
- current input 不重复。
- semantic-only world-book entry 保持可进入 prompt。
- Worker 不生成 assistant message。

## 验收红线

以下任一发生即不能 closeout：

- Phase 5 diff 包含 Chat / Prompt / DI runtime switch。
- Worker 调用 LLM、network、DB write 或生成 assistant message。
- Worker 或 source adapter 触发 WorldBook rebuild。
- Prompt switch 直接改成统一 `[Background]`，但无 request-shape 测试和用户确认。
- Chat switch 后 current input 重复。
- 文档把未实现内容写成当前实现。
- Xcode project 签名配置漂移。

## 完成定义

- 每阶段 focused tests 通过，或明确记录 NOT RUN / blocked 原因。
- Phase 6 后至少跑一次 Prompt + Chat focused regression。
- Full suite 如未跑，harness 必须写明原因和剩余风险。
- `git diff --check` 通过。

## 写回要求

- Source：新增测试必须随 source 同阶段提交或记录。
- Docs：按阶段同步 arch，不允许只更新 plan。
- Harness：记录命令、结果、suite/test count、xcresult 路径、失败/跳过原因。
