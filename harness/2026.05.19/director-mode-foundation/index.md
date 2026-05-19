# Director Mode Foundation Closeout

> 日期：2026-05-19
> 范围：`docs/superpowers/plans/2026-05-19-director-mode-foundation/`
> 结论：Director contract foundation 已落地；Director runtime、Stage DB/UI、多角色输出未实现。

## 1. 完成内容

本轮按计划只落 Director / 导演模式的 Core contract 和 focused tests：

- `OpenChat/Core/Stage/DirectorMode.swift`
- `OpenChat/Core/Stage/StageInstruction.swift`
- `OpenChat/Core/Stage/DirectorPlan.swift`
- `OpenChat/Core/Stage/DirectorDiagnostics.swift`

新增 / 更新 tests：

- `OpenChatTests/Core/StageTests/DirectorContractTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`

`ruby scripts/generate_xcodeproj.rb` 已运行，使新增 Swift source/test 进入 target。脚本本身未修改，签名关键值保持脚本配置：

- app bundle id：`fukujusou.openchat.com`
- development team：`GZAC7644XS`
- code sign style：`Automatic`
- test bundle id：`com.openchat.app.tests`

## 2. Contract 证据

已落地的 contract：

- `DirectorMode`: `silent`、`agent`、`userControlled`，raw value / Codable / CaseIterable 已测试。
- `StageInputRole`: `participant` / `director`，表示输入语义；`director` 不等于普通 chat user message role。
- `StageInstruction`: 支持 user / director agent / system default source；默认 `hiddenFromCharacters`；空白 content 抛出 `StageInstructionError.emptyContent`。
- `DirectorInput`: 保存 mode、input role、current input、recent instruction ids。
- `SpeakerTurn`: 仅是 speaker plan hint，允许 unresolved participant / character id。
- `DirectorPlan`: 只包含 stage instructions、speakerPlan 和 diagnostics，不包含 assistant text、API messages 或 persistence operation。
- `DirectorDiagnostics`: 只承载 warnings、omitted instruction ids、policy profile 和 metadata，不承载 user-visible assistant draft。
- `StagePromptLayerPlan`: 纯 order contract helper，锁定 future `directorInstructions` 位于 `currentBackground` 之后、`currentTurn` 之前。

Agent policy 证据：

- deterministic director 不含 `.llm`、`.webSearch`、`.databaseWrite`、`.userVisibleDraft`。
- LLM director 可含 `.llm`，但仍禁用 web search、network tools、database write 和 user-visible draft。
- persistent write 仍要求 confirmation。

## 3. 传播审计

审计模式：窄范围增量传播审计。

实际传播面：

- 新增 `OpenChat/Core/Stage/*`。
- 新增 `OpenChatTests/Core/StageTests/DirectorContractTests.swift`。
- 扩展 `AgentPolicyTests`。
- 运行 generator 更新 `OpenChat.xcodeproj/project.pbxproj` 和 scheme target references。
- 同步 Stage arch、PLANING、AntiEntropy 和本 harness。

未传播到：

- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
- `OpenChat/Core/Database/Records/MessageRecord.swift`
- `OpenChat/Features/Chat/Views/InputBarView.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/Background/*`
- `OpenChat/Resources/Localizable.xcstrings`

行为结论：Director foundation 仍是纯 Core contract。当前主聊天路径仍是 `ChatViewModel.generateResponse -> BackgroundManager.prepare -> PromptAssembler -> ContextManager -> APIClient.streamMessage`，未接入 DirectorPlan。

## 4. 三边一致性

| 边 | 结果 | 证据 |
|---|---|---|
| `arch-src` | 一致 | `arch/modules/stage/director.md`、`prompt-flow.md`、`migration-plan.md` 已写回 Director contract 已落地，同时保留 runtime / UI / DB / prompt injection 未实现边界。 |
| `arch-test` | 一致 | `DirectorContractTests` 覆盖 mode raw values、Codable、stage instruction validation、silent empty plan、userControlled input semantics、diagnostics 和 prompt layer order；`AgentPolicyTests` 覆盖 director policy 红线。 |
| `src-test` | 一致 | Focused Director / AgentPolicy 16 tests / 2 suites passed；Prompt / Chat / Background regression 40 tests / 4 suites passed；full suite 372 tests / 67 suites passed。 |

## 5. 验证记录

Simulator discovery:

```bash
xcrun simctl list devices available | rg 'iPhone'
```

沙箱内第一次因 CoreSimulatorService/log 权限失败；提权重跑后成功列出可用 `iPhone 17 Pro`、`iPhone 17` 等 devices。

Focused Director / AgentPolicy:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/DirectorContractTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：16 tests / 2 suites passed，`** TEST SUCCEEDED **`。

xcresult:

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-16-00-+0800.xcresult
```

Prompt / Chat / Background regression:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

第一次结果：failed before test body; simulator launch preflight Busy，未进入 Swift Testing assertions。xcresult:

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-16-39-+0800.xcresult
```

重跑命令：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：40 tests / 4 suites passed，`** TEST SUCCEEDED **`。

xcresult:

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-17-33-+0800.xcresult
```

Full suite:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=F8D0D88B-71FD-471F-855A-B2B5D8267117'
```

结果：372 tests / 67 suites passed，`** TEST SUCCEEDED **`。

xcresult:

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-23-28-+0800.xcresult
```

Whitespace check:

```bash
git diff --check
```

结果：通过，无 whitespace errors。

## 6. 剩余边界

本轮仍未实现：

- Director executor / controller / runtime。
- Stage runtime、Stage DB schema、Stage persistence、Stage UI。
- 输入栏“作为用户 / 作为导演”切换。
- Multi-character participant binding。
- `MessageRecord` speaker metadata。
- Multi-speaker output parser 或 tagged / JSON roleplay output。
- DirectorPlan 注入 `ChatViewModel.generateResponse(...)`。
- Director Instructions 注入 production `PromptAssembler` request body。
- Responses API Stage request-shape guarantees。
- Exa / LibMan / web search。
- 普通角色 AgentCore agent 化或 tool call。
- Director diagnostics UI。

该 closeout 只能解读为 contract foundation landed，不能解读为 Director Mode 已可在聊天中使用。
