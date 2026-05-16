# 06. 测试与验收

## Baseline

实施前记录当前工作区：

```bash
git status --short
```

建议先跑主链路 focused baseline，确认 AgentCore 新增前 Chat / Prompt / Memory / WorldBook 是稳定的：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

如 simulator 名称不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## Phase tests

| 阶段 | 必跑测试 |
|---|---|
| A | `AgentDescriptorTests`, `AgentPolicyTests` |
| B | `DeterministicAgentExecutorTests`, `AgentDiagnosticsTests` |
| C | 文档审计，无新增 runtime tests |
| Closeout | AgentCore focused + 主链路 focused；如 source 已改，最终 full suite |

## AgentCore focused command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/AgentDescriptorTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests' '-only-testing:OpenChatTests/AgentDiagnosticsTests'
```

如果测试 target 名称因 Swift Testing discovery 不接受单个 suite 名称，可改跑目录内相关 suite 或直接跑 full `OpenChatTests` focused set，并在 evidence 中记录实际命令。

## Regression focused command

AgentCore 不应影响主聊天链路，因此 closeout 需要重跑：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

## Full suite

源码实施完成后最终运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

如果遇到 simulator `Busy` / preflight failure，换用 `xcrun simctl list devices available | rg 'iPhone'` 中的可用设备，并记录实际 device name / id。

## 文档写回

实现完成后至少同步：

- `arch/modules/agent-core.md`：把对应 contract 从规划改为已实现，并列出源码 / 测试证据。
- `arch/modules/background/background-worker.md`：说明 BackgroundWorker 将复用已实现 AgentCore contract，但 worker 本身仍未实现。
- `PLANING.md`：Phase 3 状态从 “AgentCore foundation contract 当前入口” 更新为 “AgentCore foundation 已完成；下一步 Memory / WorldBook read-only source tool 暴露，然后才是 Background DTO + deterministic worker”。
- `harness/<date>/agent-core-foundation/index.md`：如果进入源码实施，记录 focused / full suite 命令和结果。

2026-05-17 closeout evidence：

- `ruby scripts/generate_xcodeproj.rb` 已运行；`OpenChat.xcodeproj/project.pbxproj` 包含新增 AgentCore source/test membership，scheme target UUID 随 generator 更新。
- AgentCore focused command：12 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Regression focused command：50 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：303 tests / 58 suites passed，`** TEST SUCCEEDED **`。
- `arch/modules/agent-core.md`、Background / Stage / LibMan readiness docs、`PLANING.md`、`arch/AntiEntropy/propagation-audit.md`、`arch/AntiEntropy/triangle-consistency.md` 和 `harness/2026.05.17/agent-core-foundation/index.md` 已做 closeout writeback。
- 2026-05-17 docs-only 顺序修正：AgentCore 后的下一步改为 Memory / WorldBook source tool 暴露；BackgroundWorker 不再作为紧邻下一计划包入口。

## 完成定义

- `Core/AgentCore` 编译通过。
- 三类 consumer policy profile 有测试锁定。
- deterministic executor 会拒绝 LLM、web/network、database write。
- diagnostics 能记录 selected / omitted / fallback / errors。
- 没有 Chat、Prompt、Memory、WorldBook、Database、Networking 行为变化。
- Xcode project 包含新增 Swift 文件，且签名配置无手工漂移。
- focused AgentCore tests 与主链路 regression focused tests 通过。
- full suite 通过；如有 baseline failure，必须明确不是本轮回归并写入 evidence。
