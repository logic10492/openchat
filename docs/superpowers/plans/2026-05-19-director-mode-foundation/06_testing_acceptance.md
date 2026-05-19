# 06. Testing Acceptance

## 分阶段测试矩阵

| 阶段 | 必跑 focused tests | 目的 |
|---|---|---|
| S0 | `AgentPolicyTests` | 确认 director policy 前置边界 |
| 6A | future `DirectorContractTests` | DTO raw value / Codable / empty plan / validation |
| 6B | `DirectorContractTests`、`AgentPolicyTests` | 三种 mode 与 policy red lines |
| 6C | contract helper tests if added | Director Instructions prompt-order contract |
| Closeout | `PromptAssemblerTests`、`ChatViewModelPromptAssemblyTests` | 确认未改坏当前主链路 |

## 基线命令

```bash
git status --short --branch
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/AgentPolicyTests'
```

## 实施后 focused 命令

新增 Director contract tests 后：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/DirectorContractTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

主链路 regression：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/AgentPolicyTests'
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

- `DirectorMode` raw values。
- `StageInputRole` raw values。
- `DirectorPlan` Codable round trip。
- silent mode empty plan。
- agent mode policy 不开放 web / network / DB write。
- userControlled mode 默认生成 stage instruction，不生成 ordinary user chat message。
- DirectorPlan 不包含 assistant message content。
- 如果新增 prompt boundary helper，验证 Director Instructions 在 Current Turn 前。

## 验收红线

以下任一发生即不能 closeout：

- 新增 DB migration。
- 修改 `ConversationRecord` / `MessageRecord` 持久字段。
- 修改 Chat UI / InputBar UI。
- 修改 production `PromptAssembler` request shape 但没有 request-shape tests。
- 把 DirectorPlan 保存为 assistant message。
- 让 Director policy 开放 web search、network tool 或 database write。
- 把普通角色纳入 AgentCore runtime。
- 文档把 Stage / Director runtime 写成当前已实现。
- Xcode project 签名配置漂移。

## 完成定义

- 每阶段 focused tests 通过，或明确记录 NOT RUN / blocked 原因。
- Phase 6 后至少跑一次 AgentPolicy focused test。
- 如有 Swift source 改动，跑 Prompt / Chat regression。
- Full suite 如未跑，harness 必须写明原因和剩余风险。
- `git diff --check` 通过。

## 写回要求

- Source：新增 tests 必须随 source 同阶段提交或记录。
- Docs：按阶段同步 arch，不允许只更新 plan。
- Harness：记录命令、结果、suite/test count、xcresult 路径、失败/跳过原因。
