# Prompt Four-Layer Assembly Propagation Audit

> 日期：2026-04-30
> 模式：窄范围增量审计
> 范围：`OpenChat/Core/PromptEngine/`、`OpenChatTests/Core/PromptEngineTests/`、`OpenChatTests/Features/ChatTests/`、Prompt/AntiEntropy/roadmap 相关文档

## 结论

本轮 Prompt 四层拼装改动的传播面限定在 `Core/PromptEngine` 与测试/文档。`ChatViewModel -> PromptAssembler.preview -> ContextManager.prepareHistory -> PromptAssembler.assemble -> APIClient` 调用链没有改变，ContextManager 仍只处理过滤后的历史消息。最终 request 顺序已由 Core 单元测试和 Chat 发送链路测试共同锁定。

## 静态传播面

| 项 | 结果 |
|---|---:|
| App Swift files | 106 |
| Test Swift files | 31 |
| Production Swift 改动 | 3 |
| Test Swift 改动 | 2 |

Production 改动：

- `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/PromptEngine/PromptSegment.swift`

静态边界判断：

- 未新增 Swift import 依赖；PromptEngine 变更文件仍只显式 `import Foundation`。
- 未修改 `ChatViewModel+Support.swift` 生产调用链。
- 未修改数据库 migration、签名配置或 Xcode project。
- Feature 层改动只发生在测试文件，不扩大生产 Feature 依赖面。

## 行为传播链路

目标链路：

`ChatViewModel+Support.generateResponse -> PromptAssembler.preview -> ContextManager.prepareHistory -> PromptAssembler.assemble -> APIClient.streamMessage`

源码证据：

- `PromptAssemblyPreview` 输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
- `PromptAssembler.preview(...)` 生成 Stable Identity、Current-Turn Context、Current Turn，并用这些不可裁剪段计算 `fixedTokens`。
- `ContextManager.prepareHistory(...)` 继续只接收 `fixedTokens` 和过滤后的 history，返回 Stable Conversation State。
- `PromptAssembler.assemble(...)` 输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
- 世界书 position 字段只保留为兼容字段；命中条目统一进入 `[World Book Entries]` block。
- 示例对话统一进入 `[Example Dialogs]` block；记忆统一进入 `[Memories]` block；时间上下文进入最后一条 user message。

## 三边一致性

### arch-src

- `arch/modules/prompt-assembly.md` 已改为 implemented 四层顺序和当前源码证据。
- `.github/instructions/prompt-engine.instructions.md` 已同步四层顺序、labeled blocks 和 time-in-current-turn 约束。
- `arch/index.md`、`arch/modules/chat.md`、`arch/modules/world-book.md`、`arch/modules/memory/index.md`、`arch/data-model.md` 已清理旧 position/时间/示例对话描述。

### arch-test

- `PromptAssemblerTests` 覆盖四层顺序、preview 四层结构、world book position 兼容、labeled blocks、time-in-current-turn。
- `ChatViewModelPromptAssemblyTests` 覆盖真实 API request 的 history -> example -> memory -> current turn 顺序，以及当前输入只出现一次。

### src-test

- Focused prompt suite：13 tests passed。
- Focused chat prompt suite：9 tests passed。
- Combined prompt/chat suite：22 tests passed。
- Full suite：197 tests / 41 suites passed，`** TEST SUCCEEDED **`。

## 风险与后续

- 当前改动没有扩大生产 import 面，也没有触碰 migration / signing / project generation。
- Prompt block 包装会改变实际模型输入形态，这是本计划目标行为；风险由 Core 与 Feature 发送链路测试覆盖。
- Feature 分层漂移仍是既有风险，继续由 `arch/AntiEntropy/layering-repair-plan.md` 跟踪，不在本轮 Prompt 改动中修复。
