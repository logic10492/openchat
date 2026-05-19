# Stage Runtime Foundation Closeout

> 日期：2026-05-19
> 范围：Stage / Director runtime、Stage DB/UI、多角色同场单 speaker 输出、用户导演输入。
> 结论：本轮目标已完成；仍保留 LLM Director agent、多 speaker parser、Responses Stage snapshot 和 XCUITest 为后续计划。

## 1. 完成内容

Stage persistence：

- `OpenChat/Core/Database/Migrations.swift` 追加 `v18_create_stage_tables`。
- 新增 `StageRecord`、`StageParticipantRecord`、`StageInstructionRecord`。
- `MessageRecord` 追加 `stageId`、`speakerKind`、`speakerId`、`speakerName`。
- `DatabaseManager+Stage` 提供 stage context、create、director mode、participant add/remove、instruction save API。

Director runtime：

- `StageModels.swift` 定义 `StageParticipantVisibility`、`MessageSpeakerKind`、`StageContext`、`StageTurnPlan`。
- `DirectorController` 提供 deterministic speaker selection：输入点名优先，否则选择 sortOrder 最小的 active present participant。
- `DeterministicDirectorExecutor` 接入 `ChatViewModel+Support.generateResponse(...)`。

Chat / UI：

- `ChatSettingsSheet` 提供 Enable Stage、Director Mode、participants add/remove。
- `InputBarView` 在 Stage enabled 时显示 participant / director segmented picker。
- director input 写入 `stage_instruction`，不写普通 user message，不触发 title generation 或 API request。
- participant input 走 Stage prompt 主链路，并保存 user/assistant speaker metadata。
- `MessageBubbleView` 优先显示 `speakerName`。

Prompt：

- `PromptAssembler.preview(...)` / `assemble(...)` 新增 `stageTurnPlan` 兼容参数。
- Stage prompt 注入 `[Stage]`、`[Stage Participants]`、`[Director Instructions]`。

Docs / anti-entropy：

- 已同步 `arch/modules/stage/*`、`arch/data-model.md`、`PLANING.md`。
- 已追加 `arch/AntiEntropy/propagation-audit.md` 与 `triangle-consistency.md` 本轮写回。

## 2. 需求到证据

| 用户要求 | 状态 | 证据 |
|---|---|---|
| DirectorController / Executor | 完成 | `OpenChat/Core/Stage/DirectorController.swift`、`DirectorExecutor.swift`、`DirectorContractTests` |
| DirectorPlan 接入 Chat/Stage 主链路 | 完成 | `ChatViewModel+Support.generateResponse(...)` 执行 executor，`PromptAssembler` 消费 `StageTurnPlan` |
| Stage participant / speaker / visibility DTO | 完成 | `StageModels.swift`、`MessageSpeakerKind`、`StageParticipantVisibility` |
| StageRecord / StageParticipant 持久化 | 完成 | v18 migration、Stage records、`DatabaseManager+Stage`、`MigrationTests` |
| Stage 创建入口 | 完成 | `ChatSettingsSheet` Enable Stage -> `ChatViewModel.enableStage()` |
| 多角色绑定 | 完成 | `stage_participant` unique stage/card binding，Add Participant picker，two-participant Chat test |
| speaker metadata | 完成 | `message` speaker columns，assistant metadata persistence test |
| 用户导演输入 UI | 完成 | `InputBarView` participant/director segmented picker |
| 导演输入持久化与 history 隔离 | 完成 | `test_directorInput_isPersistedAsStageInstructionNotUserMessage` |

## 3. 验证摘要

Focused Stage / migration / chat：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/DirectorContractTests' '-only-testing:OpenChatTests/MigrationTests'
```

结果：68 tests / 3 suites passed，`** TEST SUCCEEDED **`。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=F8D0D88B-71FD-471F-855A-B2B5D8267117'
```

结果：378 tests / 67 suites passed，`** TEST SUCCEEDED **`。

Other checks：

- `git diff --check` passed。
- `python3 -m json.tool OpenChat/Resources/Localizable.xcstrings` passed。
- Xcode full-suite build also ran `xcstringstool compile` successfully for `Localizable.xcstrings`。
- Signing values still match `scripts/generate_xcodeproj.rb`: `PRODUCT_BUNDLE_IDENTIFIER = fukujusou.openchat.com`、`DEVELOPMENT_TEAM = GZAC7644XS`、`CODE_SIGN_STYLE = Automatic`。

完整命令、xcresult 和边界见 `evidence.txt`。

## 4. 剩余边界

未实现：

- LLM Director agent / AgentCore executor wiring。
- `agent` mode 生成 LLM `DirectorPlan`。
- 多 speaker output parser、speaker block schema、parser diagnostics 和一轮多 assistant message 拆分。
- Responses API 下 Stage system block folding snapshot。
- Stage 独立列表页。
- Stage 创建、DirectorMode、participant add/remove、director input 的 XCUITest。
- Stage participant / director instruction 尚未作为 `BackgroundManager` source request filter。

本轮实现不改变以下原则：

- 普通角色仍不是 AgentCore agent。
- 普通角色没有 tool call 权限。
- Director 不替角色写最终台词。
