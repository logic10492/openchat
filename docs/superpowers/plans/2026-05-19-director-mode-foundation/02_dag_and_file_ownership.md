# 02. DAG 与文件归属

## DAG

```text
S0 source baseline + propagation audit
  -> 6A Director contract types
  -> 6B mode / policy boundary tests
  -> 6C stage instruction + prompt boundary contract
  -> closeout docs + harness
```

## 并行窗口

可以并行：

- Lane A：传播审计与 file ownership，确认 Phase 6 不碰 DB/UI/Chat 主链路。
- Lane B：Director DTO contract 草案，设计 `DirectorMode` / `StageInstruction` / `DirectorPlan`。
- Lane C：AgentCore policy / mode boundary tests，补齐 `directorDefault` 与三种模式测试。
- Lane D：Stage instruction prompt boundary，整理 Director Instructions 的目标位置和 request-shape 风险。

不可并行：

- DTO raw values 未稳定前，不写 prompt boundary tests。
- mode policy 未稳定前，不写 Director executor 草案。
- 没有 Stage persistence 计划前，不改 `ConversationRecord` / `MessageRecord`。
- 没有 UI 计划前，不改 `InputBarView` 或 Localizable keys。

## 文件归属

| 阶段 | 允许 source | 测试 | 文档写回 |
|---|---|---|---|
| S0 Baseline | 无 source 改动 | 无 | 本计划包 `00_source_baseline.md` |
| 6A Contract types | 计划：`OpenChat/Core/Stage/*.swift` 或经审计确认后的等价 Core 目录 | `OpenChatTests/Core/StageTests/DirectorContractTests.swift` | `arch/modules/stage/director.md`、`multi-character.md` |
| 6B Mode / policy | `OpenChat/Core/Stage/*.swift`；必要时只补 `AgentPolicy.swift` helper，不改变既有 policy 语义 | `DirectorContractTests.swift`、`AgentPolicyTests.swift` | `arch/modules/stage/director.md`、`arch/modules/agent-core.md` |
| 6C Prompt boundary contract | DTO/helper only；默认不改生产 `PromptAssembler` | future `StagePromptContractTests.swift` 或 contract-level tests | `arch/modules/stage/prompt-flow.md`、`migration-plan.md` |
| Closeout | 无 source 改动 | 根据实现结果运行 focused / full suite | `PLANING.md`、`arch/AntiEntropy/*`、`harness/<date>/director-mode-foundation/` |

## 禁改面

Phase 6 禁止修改：

- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
- `OpenChat/Core/Database/Records/MessageRecord.swift`
- `OpenChat/Features/Chat/Views/InputBarView.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift` 的生产主链路
- `OpenChat/Core/Background/*` 的 production behavior
- `OpenChat/Resources/Localizable.xcstrings`
- `scripts/generate_xcodeproj.rb`，除非新增 Swift 文件 target membership 需要按既有流程生成 project
- 签名配置

## 需审批面

以下情况必须停下来请用户确认：

- 需要新增 DB migration。
- 需要把 director mode 写入 conversation/message 表。
- 需要实现输入栏“用户 / 导演”切换 UI。
- 需要把 DirectorPlan 注入当前 Chat prompt。
- 需要让 Director 调用网络、web search、DB write 或 LibMan。
- 需要让模型输出强制 JSON/tagged schema。
- 需要修改 `scripts/generate_xcodeproj.rb`。
- 需要改变签名配置。

## Xcode project 规则

新增 Swift 文件后：

1. 先确认文件是否进入 Xcode target。
2. 如 target membership 缺失，运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

3. 生成后的 `OpenChat.xcodeproj` diff 只能包含 target membership / scheme 变化，不得漂移签名配置。

## 完成定义

- 每个阶段只改自己的 ownership 面。
- Phase 6 closeout 前，`DirectorPlan` / `StageInstruction` 不会被误认为 assistant message。
- `userControlled` 的“不作为普通角色台词保存”至少有 contract test 或明确 blocked 记录。
- 没有 Stage DB/UI、多角色输出、speaker metadata 变更。
- docs / harness 记录未完成项和后续 Phase 7+ 边界。

## 推荐 staging 边界

如果拆 commit：

```text
commit 1: Director contract DTO + focused tests
commit 2: mode policy boundary tests + docs
commit 3: prompt boundary docs + harness closeout
```

如果当前工作区有 unrelated dirty files，只 stage Phase 6 Director 文件。
