# 聊天模块设计

> 所属层：`Features/Chat/`
> 依赖：Core/Networking（APIClient）, Core/PromptEngine, Core/ContextManager, Core/Database, Features/CharacterCard, Features/WorldBook

## 1. 功能范围

- 消息列表展示（支持 Markdown 渲染）
- 流式输出实时显示
- 发送消息 / 停止生成
- 重新生成最后一条 AI 回复
- 编辑已发送的用户消息（编辑后重新生成）
- 当前会话设置（上下文策略；非 Stage 会话支持角色卡/世界书切换，Stage 会话通过 Stage participants 管理角色）
- 会话信息展示（顶部角色胶囊；token 使用情况保留在消息统计区域，不在导航栏常驻显示）
- 每条 AI 回复下方显示详细统计（输入/输出 token 数、TPS、上下文窗口剩余百分比），可在全局设置中关闭详细模式，关闭后仅在窗口余量 < 20% 时显示上下文窗口剩余百分比
- 记忆提取完成时在对话中显示临时提示（"已提取 N 条记忆"，3 秒后自动消失）

> Stage 规划：Chat 当前是单会话/单主角色实现。多角色共同参与、导演 agent 和用户导演输入属于目标 Stage 系统，详见 `arch/modules/stage/index.md`。

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `ChatView.swift` | 聊天页面 shell：绑定 `ChatViewModel`、导航栏角色胶囊、设置/编辑 sheet、输入栏和消息 timeline 组合 |
| `ChatMessageTimelineView.swift` | Telegram 式消息轨道：日期分隔、同发送者短间隔分组、流式自动跟随/用户拖动暂停、记忆提取提示和诊断 trace 插入 |
| `ChatChromeViews.swift` | 聊天 chrome 组件：背景、日期分隔、顶部角色胶囊、角色/世界书 popover、编辑消息 sheet |
| `ChatEdgeEffects.swift` | 消息 viewport 边缘效果：顶部/底部内容渐隐、iOS 26 系统 scroll edge soft style、iOS 17-25 material mask fallback |
| `MessageBubbleView.swift` | 单条消息行和气泡，支持 Markdown、长按菜单、分组尾部时间、流式光标和统计展示 |
| `MessageBubbleChrome.swift` | 系统消息胶囊、时间脚等气泡辅助 chrome |
| `ReasoningDisclosureView.swift` | AI 思考内容展示：折叠摘要、固定高度滚动预览、长文本尾部截断与系统复制 |
| `InputBarView.swift` | 底部 composer（文本框 + 发送/停止按钮 + Stage 工具入口） |
| `DirectorResponderPanel.swift` | Stage responder 选择与排序面板 |
| `ChatSettingsSheet.swift` | 当前会话设置面板 |
| `ChatViewModel.swift` | 核心 ViewModel，管理消息状态、调度 API 请求 |
| `ChatViewModel+Support.swift` | 生成/流式/记忆提取的实现细节 |
| `MessageDisplayItem.swift` | 消息展示用 DTO（含可选 StreamingStats） |
| `StreamingStats.swift` | 流式输出统计数据（输入/输出 token、TPS、上下文余量） |
| `StatsBarView.swift` | 统计数据展示组件（详细/精简两种模式） |

## 3. 视图设计

### 3.1 ChatView（主界面）

```
┌─────────────────────────────────────────┐
│ [←]       艾拉                  [⚙️] │  ← 导航栏：液态玻璃角色胶囊 + 设置
│          银月森林                      │  ← 胶囊副标题：仅角色卡绑定世界书时显示
│─────────────────────────────────────────│
│                                         │
│        ┌────────────────────────────┐   │
│        │ 你好，请问你是谁？         │   │  ← 用户消息：右侧扁平气泡
│        └────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 我是艾拉，银月森林的守护者。     │   │  ← AI 消息：左侧扁平气泡
│  │ 有什么我能帮助你的吗？           │   │
│  └──────────────────────────────────┘   │
│                                         │
│        ┌────────────────────────────┐   │
│        │ 这里是哪里？               │   │  ← 长按气泡：复制 / 编辑
│        └────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 这里是银月森林的入口...          │   │  ← 可重新生成：动作栏 / 长按菜单
│  │ 前方就是精灵族的领地了。█        │   │  ← 流式输出光标
│  └──────────────────────────────────┘   │
│                                         │
│─────────────────────────────────────────│
│ [输入消息...]                    [■停止]│  ← 生成中显示停止按钮
│ [输入消息...]                    [➤发送]│  ← 空闲时显示发送按钮
└─────────────────────────────────────────┘
```

顶部胶囊规则：
- 非 Stage 会话显示当前角色卡名；如果角色卡绑定世界书，第二行用次要文字显示世界书名；未绑定世界书时不显示副标题。
- 点击非 Stage 胶囊在胶囊下方弹出 SwiftUI popover，而不是展开胶囊本体；胶囊本体不显示 chevron 或其他展开暗示。
- popover 上半部分是“可选世界书”：包含“无世界书”和所有世界书；选择世界书只更新下半部分筛选，不立即保存会话。
- popover 下半部分是“世界书可选角色”：展示当前世界书下的角色；“无世界书”筛选下展示未绑定世界书的角色。选择角色后更新 `selectedCharacterCardID` 并复用 `ChatViewModel.saveConversationSettings()` 保存到当前会话。
- Stage 会话本轮只做简单兼容：胶囊显示 `Stage` 与当前 active/present participants 摘要，点击进入设置，不通过胶囊切换会话级角色卡。

实现证据：`ChatView.swift` 只保留页面级 binding、toolbar、sheet 和 `ChatMessageTimelineView` / `InputBarView` 组合；principal toolbar 使用 `ChatHeaderCapsule` 渲染角色胶囊。`ChatChromeViews.swift` 的 `ChatHeaderGlassCapsuleStyle` 在 iOS 26+ 使用原生 `glassEffect(.regular.interactive(), in: Capsule())`，在 iOS 17-25 保留 `.ultraThinMaterial` fallback。非 Stage 分支通过 `Button + popover` 展示 `CharacterPickerPopover`，由 `availableWorldBooks` 与 `availableCharacterCards` 组成世界书筛选和角色列表，并在角色选择时调用 `selectCharacterCard(_:)`；Stage 分支仅作为设置入口。消息滚动、日期分隔、分组和流式跟随由 `ChatMessageTimelineView.swift` 承担，避免 `ChatView.swift` 再次膨胀为聊天行为大杂烩。顶部/底部控件下方的边缘视觉由 `ChatEdgeEffects.swift` 承担：`ChatView.swift` 只用 `ChatEdgeEffectViewport` 包住消息列表，实际输入栏仍由 `chatInputBar` 挂载在更高层；`ChatMessageTimelineView.swift` 在 ScrollView 上调用 `openChatScrollEdgeEffects()`，iOS 26+ 使用系统 `scrollEdgeEffectStyle(.soft, for: [.top, .bottom])`，iOS 17-25 由透明 `.ultraThinMaterial` 渐变 mask 作为 fallback。该实现只影响消息 viewport，不进入 `InputBarView`。

### 3.2 MessageBubbleView

**布局规则**：
- user 消息：右对齐，主题色背景
- assistant 消息：左对齐，次要色背景，不展示头像或头像占位
- system 消息：居中，淡灰色，小字体（通常不展示给用户，除非是压缩摘要）
- 主消息列约束最大宽度，避免 iPad / 横屏下长文本铺满全屏；用户消息比助手消息更窄，保持对话阅读节奏。
- 同一发送者 / 同一 speaker / 同一天 / 5 分钟内的连续消息按 Telegram 式分组，组内压缩垂直间距，只在组尾显示时间脚。
- 时间脚内嵌在分组尾部气泡内；短消息气泡按内容自然收缩，不因时间脚或头像轨道被撑宽。
- Stage 或多角色消息可在分组首条显示 speaker 名；普通 user/assistant 身份主要由左右对齐和顶部胶囊承担；消息行内不展示头像。
- 气泡保持扁平色块，不使用液态玻璃材质；液态玻璃只用于顶部胶囊。

**内容渲染**：
- 使用 Markdown 渲染（粗体、斜体、代码块、列表等）
- 流式输出时逐步追加文本，末尾显示闪烁光标
- 展示层会把连续 3 个以上换行压缩为最多 1 个空行，避免角色输出留下大段空白；原始 message content 不改写

**思考内容展示**：
- 第一级：默认折叠，只显示 `Character Thinking` 行和生成中状态，不直接暴露思考正文。
- 第二级：点开展开后显示固定高度滚动预览。若思考内容过长，预览保留尾部上下文，前置内容用省略号表达，避免长思考链挤占主回复。预览文本启用系统文本选择，用户可通过系统复制菜单复制可见内容。
- 实现证据：`MessageBubbleView.swift` 调用 `ReasoningDisclosureView` 渲染 `MessageRecord.reasoningContent`；`ReasoningDisclosureView.swift` 负责折叠状态、固定高度预览、尾部截断和系统文本选择。

**长按菜单**：
| 消息类型 | 菜单项 |
|---|---|
| user | 编辑、复制 |
| assistant | 底部动作栏与长按菜单：复制、重新生成、删除 |
| system (压缩) | 查看原始内容 |

实现证据：`ChatMessageTimelineView.swift` 用 `MessageDisplayItem.createdAt` 插入 `ChatDateSeparator`，用 role/speaker/day/5 分钟窗口计算分组，并在用户拖动时暂停流式自动跟随。`MessageBubbleView.swift` 接收 `isGroupedWithPrevious` / `isGroupedWithNext`，不再渲染头像轨道；user 气泡使用 `Color.accentColor`，assistant 气泡使用 `Color(.secondarySystemGroupedBackground)`，两者都不使用 `.ultraThinMaterial`，并通过 `UnevenRoundedRectangle` 形成左右非对称 Telegram 式气泡尾角。`MarkdownTextView` 保持默认撑满宽度，但 chat bubble 调用 `fillsAvailableWidth: false`，让短回复按内容自然收缩。`MessageBubbleChrome.swift` 提供系统消息胶囊和内嵌时间脚；user 气泡挂载 `Edit` / `Copy` 长按菜单；assistant 气泡保留 `MessageActionBar` 并提供复制、重新生成、删除菜单。`ChatView.swift` 通过 `EditMessageSheet` 收集编辑后的文本并调用 `ChatViewModel.editMessage(...)`。

### 3.3 InputBarView

```swift
struct InputBarView: View {
    @Binding var text: String
    @Binding var inputRole: StageInputRole
    @Binding var responderIds: [String]
    var stageParticipants: [StageParticipantRecord]
    var showsDirectorTools: Bool
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCustomizeResponders: () -> Void
}
```

- 底部 composer 不再铺整宽 `.regularMaterial` 横条；底栏容器中只放透明 dock、独立圆角输入 capsule、左侧工具按钮和右侧发送按钮，键盘弹出时避免出现额外灰色横栏。
- 多行文本输入框使用 SwiftUI `TextEditor` + 隐藏测量文本自适应高度，最大 6 行，保留 `chat.inputText` accessibility identifier。
- 发送按钮：圆形 `arrow.up`，`text` 非空时启用
- 停止按钮：生成中显示圆形 `stop.fill`，点击取消当前流式请求
- 键盘 Return 不发送（允许换行），需点击按钮发送
- Stage 会话显示轻量 `ellipsis.circle` 工具按钮；展开后由 `DirectorResponderPanel.swift` 管理 responder 选择和上下排序。
- `DirectorResponderPanel.swift` 同时提供 `StageInputRole` 的 segmented picker：`Participant` 会把输入作为用户消息并触发当前 responder 队列；`Director` 会把输入保存为 hidden stage instruction，不进入消息列表。

实现证据：`ChatView.swift` 通过 `chatInputBar` 挂载 `InputBarView`：iOS 26+ 使用 `safeAreaBar(edge: .bottom, spacing: 0)`，让系统 scroll edge effect 纳入 custom bar 的 safe area 计算；iOS 17-25 fallback 到 `safeAreaInset(edge: .bottom, spacing: 0)`。`InputBarView.swift` 使用透明外层、`TextEditor`、`InputTextHeightPreferenceKey` 和独立圆角输入 capsule 实现 Telegram 式底部 composer；输入 capsule 与发送/停止圆形按钮在 iOS 26+ 使用 `glassEffect(.regular.interactive(), in:)`，在 iOS 17-25 使用 `.ultraThinMaterial` fallback，避免旧的实心白底输入槽观感。Stage 工具入口改为 `ellipsis.circle`。`DirectorResponderPanel.swift` 持有输入模式切换、director instruction 提示、responder 行、选择、上下移动和 accessibility identifiers。`UITestingSupport.swift` 的 `--ui-testing` 种子提供 Mara/Io 双角色 Stage 和 mock 流式回复，`--ui-testing-chat-edge-effects` 额外填充长消息用于顶部/底部边缘截图验证；`StageUITests.swift` 验证 director 输入不显示为消息、participant 输入生成 Mara/Io 多轮回复，并保留 `telegram-style-stage-chat` 截图附件。

### 3.4 ChatSettingsSheet

在聊天界面点击设置图标弹出的 Sheet。会话标题编辑也在该面板中完成，避免主导航栏堆叠多个操作按钮：

```
┌─────────────────────────────────────────┐
│ 会话设置                         [完成]  │
│─────────────────────────────────────────│
│ Section: 会话                            │
│   标题: [银月森林的入口]                 │
│   API 端点: [使用默认 ▸]                │
│   模型: [使用默认 ▸]                    │
│   角色卡: [艾拉 ▸]                      │
│   上下文策略: [剔除/压缩]               │
│   场景覆盖: [可选文本输入]              │
│   慢速剧情推进: [开关]                  │
│                                         │
│ Section: Stage                          │
│   导演模式 / 参与者管理                  │
│                                         │
│ Section: 模型                            │
│   本会话自定义模型参数: [开关]           │
│   关闭时展示继承的全局默认值摘要         │
│   打开后展开 Temperature / Top P /      │
│   Max Tokens / Thinking 设置             │
└─────────────────────────────────────────┘
```

模型参数继承规则：
- `conversation.modelParameters == nil` 时，`ChatViewModel.currentParameters` 从 `UserDefaults.openChatDefaultModelParameters()` 读取全局默认。
- 旧版本曾在保存会话设置时把当时的默认模型参数写入 `conversation.modelParameters`；`ChatViewModel` 会把这类 legacy 默认 JSON 视为“继承全局”，避免老会话被固定在旧默认值上。
- 只有打开 `Customize for This Chat` 时，保存设置才会把当前控件值编码到 `conversation.modelParameters`。
- 关闭本会话自定义会清空 `conversation.modelParameters`，后续生成继续继承全局默认。
- 实现证据：`ChatSettingsSheet.swift` 的 Model section 使用 `usesCustomModelParameters` 控制摘要/控件展开；`ChatViewModel.swift` 的 `currentParameters` 在会话覆盖和全局默认之间切换，并兼容 legacy 默认参数 JSON；`ChatViewModelPromptAssemblyTests.swift` 覆盖全局继承、legacy 默认参数继承、开启自定义时预填当前全局默认，以及保存时不写入覆盖的回归。

历史布局草图：

```
│ Section: 角色与世界（非 Stage 会话）     │
│   角色卡: [艾拉 ▸]          [更换/移除] │
│   世界: 中土世界（通过角色卡关联）       │
│   场景覆盖: [可选文本输入]              │
│                                         │
│ Section: 上下文管理                      │
│   策略: (●) 剔除  ( ) 压缩             │
│                                         │
│ Section: 模型参数                        │
│   Temperature: [====●=====] 0.80        │
│   Top P:       [========●=] 0.95        │
│   Max Tokens:  [====●=====] 2048        │
│                                         │
│ Section: API 端点                        │
│   当前: [本地 Llama ▸]                  │
└─────────────────────────────────────────┘
```

## 4. ChatViewModel 设计

### 4.1 状态

```swift
@Observable
final class ChatViewModel {
    // 依赖
    private let db: DatabaseManager
    private let apiClient: APIClient
    private let contextManager: ContextManager
    private let memoryManager: MemoryManager

    // 会话状态
    let conversation: ConversationRecord
    private(set) var messages: [MessageDisplayItem] = []
    private(set) var isGenerating: Bool = false
    private(set) var tokenUsage: TokenUsageReport? = nil

    // 输入状态
    var inputText: String = ""

    // 错误状态
    private(set) var error: APIError? = nil

    // 流式任务引用（用于取消）
    private var streamTask: Task<Void, Never>? = nil
}
```

### 4.2 核心方法

```swift
extension ChatViewModel {

    /// 初始加载：从 DB 读取会话消息
    func loadMessages() async

    /// 发送消息：保存用户消息 → 拼装 prompt → 流式请求 → 保存 AI 回复
    func sendMessage() async

    /// 停止生成：取消当前流式任务
    func stopGenerating()

    /// 重新生成：删除最后一条 AI 回复 → 重新发送
    func regenerateLastResponse() async

    /// 编辑消息：更新指定消息内容 → 删除该消息之后的所有消息 → 重新生成
    func editMessage(_ messageId: String, newContent: String) async

    /// 删除消息
    func deleteMessage(_ messageId: String) async
}
```

编辑语义：只允许编辑 user 消息，且生成中不接受编辑。编辑早期 user turn 时，`ChatViewModel.editMessage(...)` 会保存新的 user 内容、删除该消息 sortOrder 之后的所有 message，并删除覆盖该位置的 compression checkpoint，然后用新内容重新生成 assistant 回复。这等价于 KV cache 前缀变更后的分支截断：旧 assistant 回复和后续 user turn 不再进入新的 prompt history。

实现证据：`ChatViewModel.swift` 的 `editMessage(_:newContent:)` 先校验 `target.role == "user"`，随后调用 `deleteCompressionCheckpoints(conversationId:sourceEndAtOrAfter:)` 与 `deleteMessages(conversationId:afterSortOrder:)`，最后以 `persistUserMessage: false` 调用 `generateResponse(...)`。`ChatViewModelPromptAssemblyTests.test_editUserMessage_truncatesTailAndRegeneratesFromEditedPrefix` 覆盖 `a -> A -> b -> B -> c -> C` 编辑 `a` 后只保留 `edited a -> new response`，并验证新请求不包含旧分支内容。

### 4.3 发送消息完整流程

```
sendMessage():
    1. guard !inputText.isEmpty, !isGenerating
    2. isGenerating = true
    3. 创建 userMessage (MessageRecord) 并保存到 DB
    4. 将 userMessage 追加到 messages 列表
    5. 清空 inputText

    6. // 加载上下文
       characterCard = 从 DB 加载 conversation.characterCardId
       worldBook = 从 DB 通过 characterCard.worldBookId 加载世界书
       worldBookEntries = 从 DB 加载世界书的已启用条目
       endpoint = 从 DB 加载 conversation.apiEndpointId

    6.5 // 前置记忆提取
       若达到 pending message 阈值，ChatViewModel 在本轮生成前同步等待
       memoryManager.extractMemories(from: conversation)，让新记忆可被 Background source 召回。

    7. 从 DB 读取当前会话消息后，构造 promptHistoryMessages：
       - 乐观保存的当前 user message 保留在 DB/UI 中；
       - prompt history 中排除本轮 current input record；
       - 重新生成/编辑时排除与 currentInput 对应的最后一条 user record。

    8. 对当前 worldBook 做 bounded rebuild：
       WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit: 8)
       失败只记录 warning，不阻断生成；该 side effect 仍归 ChatViewModel。

    9. BackgroundManager.prepare(request, policy):
       - MemoryBackgroundSource 包装 MemoryRecallTool / MemoryManager.recallMemories(...)
       - WorldBookBackgroundSource 包装 WorldBookRecallTool / WorldBookSource.recallEntries(...)
       - BackgroundWorker deterministic selection 输出 BackgroundPacket
       - worldBook source failure 时保留 keyword fallback candidates

    10. PromptAssembler.preview(... backgroundPacket:) 使用 packet selected entries
        计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens。

    11. ContextManager.prepareHistory(messages:promptHistoryMessages, ...)
       只处理过滤后的历史，再由 PromptAssembler.assemble(... backgroundPacket:)
       输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
       tokenUsage = result.tokenUsage

    12. // 创建空的 assistantMessage 占位
        assistantMessage = MessageRecord(role: "assistant", content: "")
        保存到 DB
        追加到 messages 列表

    13. // 流式请求
        streamTask = Task {
            do {
                let stream = apiClient.streamMessage(
                    messages: result.messages,
                    endpoint: endpointConfig,
                    parameters: modelParams)

                for try await delta in stream {
                    assistantMessage.content += delta.content
                    更新 messages 中对应项的显示内容（触发 UI 刷新）

                    if delta.finishReason != nil {
                        break
                    }
                }

                // 完成：更新 token 计数并保存
                assistantMessage.tokenCount = TokenCounter.count(assistantMessage.content)
                更新 DB 中的 assistantMessage

            } catch is CancellationError {
                // 用户取消：保存已生成的部分内容
                更新 DB 中的 assistantMessage（保留已有内容）

            } catch {
                self.error = error as? APIError
                // 删除空的 assistantMessage
                从 DB 和 messages 列表中移除
            }

            isGenerating = false
            streamTask = nil
        }
```

### 4.4 重新生成流程

```
regenerateLastResponse():
    1. guard let lastAssistant = messages.last(where: { $0.role == "assistant" })
    2. 从 DB 和 messages 中删除 lastAssistant
    3. 将 inputText 设为空（不需要新的用户输入）
    4. 执行与 sendMessage() 步骤 6-11 相同的流程
       （但使用已有的最后一条 user 消息作为 currentInput）
```

### 4.5 编辑消息流程

```
editMessage(messageId, newContent):
    1. 找到 messageId 在 messages 中的位置 idx
    2. 更新该消息的 content 为 newContent，保存 DB
    3. 删除 idx 之后的所有消息（DB + messages 列表）
    4. 执行重新生成流程
```

### 4.6 记忆提取触发

当前源码在用户消息持久化后，从 DB 读取 `conversation.lastExtractedSortOrder` 与消息列表，计算 `sortOrder > cutoff` 的待提取消息数；当待提取消息数达到 `ChatViewModel.minimumPendingMessagesForExtraction == 4` 时，在**当前 `generateResponse` 中同步等待**记忆提取完成（在检索记忆之前）：

```swift
// Pre-response extraction in generateResponse:
if try await shouldExtractMemories(for: conversation),
   characterCard?.id != nil {
    extractionPhase = .extracting
    let result = try await memoryManager.extractMemories(from: conversation)
    extractionPhase = result.isEmpty ? .skipped : .completed(...)
}
// Then BackgroundManager.prepare(...) can recall newly extracted memories.
```

- **触发时机**：发送链路内的前置同步提取（位于用户消息持久化之后、记忆检索之前）；`ChatView.onDisappear` 保留 fire-and-forget 调用
- **UI 反馈**：通过 `extractionPhase` 状态驱动 `MemoryExtractionIndicator` 内联指示器，显示"正在提取 / 已提取 N 条 / 提取失败"
- **cutoff 边界**：使用 `conversation.lastExtractedSortOrder`（基于 message sortOrder）替代旧的 `latestMemoryDate`（基于 memory_entry.createdAt），避免并发写入导致消息被跳过
- **错误反馈**：提取失败记录日志并在 UI 显示错误指示器，不阻塞后续生成

## 4.7 Background 主链路切换

2026-05-17 Phase 6 后，Chat 主链路不再直接把 `MemoryManager.retrieveMemories(...)` 和 `WorldBookSource.recallEntries(...)` 的数组交给 PromptAssembler。当前源码事实：

- `OpenChat/App/DependencyContainer.swift` 装配 `BackgroundManager`，其 sources 为 `MemoryBackgroundSource(tool: MemoryRecallTool(memoryManager: ...))` 与 `WorldBookBackgroundSource(tool: WorldBookRecallTool(source: ...))`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` 在 `generateResponse(...)` 中构造 `BackgroundRequest`，调用 `backgroundManager.prepare(...)`，再调用 packet-aware `PromptAssembler.preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)`。
- bounded `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 仍由 ChatViewModel 在 manager prepare 前执行；`BackgroundWorker` 与 source adapter 不触发 rebuild。
- `BackgroundManager` 对单 source failure 做降级；worldBook source failure 使用旧 keyword fallback 生成 `.worldBook` candidates。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 覆盖 request body 使用 packet selected entries、current input 不重复、semantic-only world book entry 进入 `[World Book Entries]`、semantic failure keyword fallback 保持可用。

## 5. MessageDisplayItem

```swift
struct MessageDisplayItem: Identifiable {
    let id: String
    let role: String
    var content: String           // 可变：流式输出时逐步更新
    var contentBlocks: [TextContentBlock] // 渲染分块，降低超长流式输出的单次更新范围
    var contentRenderRevision: Int        // 流式内容修订号，驱动滚动跟随与 diff
    let isCompressed: Bool
    let originalContent: String?  // 压缩消息的原始内容
    let createdAt: Date

    init(from record: MessageRecord)
}
```

## 6. 流式输出的 UI 更新策略

### 6.1 分块流式渲染

流式 SSE 事件仍然逐 chunk 进入 UI，保证用户看到实时输出；但 assistant 正文不再作为单个大文本整体重算：

- `MessageDisplayItem.appendContentDelta(...)` 同步维护完整 `content` 与 `contentBlocks`
- `TextContentBlock` 优先按自然换行切块，超长无换行文本按固定上限兜底切块
- `MessageBubbleView` 传入 `contentBlocks`，由 `MarkdownTextView` 分块渲染，避免每个 SSE chunk 都让整条长回复重新参与 Markdown / Text 构建
- `contentRenderRevision` 只表达流式文本修订，不把完整 content 放入 Hashable diff 热路径

### 6.2 Markdown 延迟刷新与缓存

RP 文本默认以 plain Text 先显示；Markdown 渲染作为延迟增强，不阻塞逐 chunk 输出：

- `MarkdownRenderPolicy.refreshDelay(forCharacterCount:)` 按全文长度返回 30 / 50 / 75 / 100ms 的延迟，文本越长越 lazy
- 每个 `TextContentBlock` 独立执行 Markdown parse
- `MarkdownRenderCache` 缓存已解析或失败的 block，避免相同块重复解析
- 当前实现使用 `.inlineOnlyPreservingWhitespace`，保持原有 inline Markdown 行为

### 6.3 自动滚动

- 消息列表使用 `ScrollViewReader`
- 新用户消息到达和生成开始时滚动到底部
- 流式内容更新时仅在 `viewModel.isGenerating && shouldFollowStreaming == true` 时跟随到底部
- 用户上滑后暂停跟随；拖动/按住期间不恢复
- 手势结束且 0.5s 内没有新的触摸事件后，仅当本轮仍在生成时恢复跟随并立即滚回底部
- 生成结束会取消待恢复的跟随任务，不再触发最终跳底；用户可自由拖动历史消息

### 6.4 流式光标

- 生成中的 AI 消息末尾显示闪烁的 `█` 光标
- 生成完成后光标消失

## 7. Token 使用情况展示

点击导航栏的 📊 图标弹出 Popover：

```
┌──────────────────────────┐
│ Token 使用情况            │
│──────────────────────────│
│ 总预算: 1638 / 4096      │
│ ████████░░░░░░░░ 40%     │
│──────────────────────────│
│ System Prompt:    120    │
│ 角色描述:          85    │
│ 场景:              42    │
│ 世界书 (3条):     230    │
│ 示例对话:         180    │
│ 历史 (12条):      850    │
│ 当前输入:          31    │
│──────────────────────────│
│ 已用: 1538  剩余: 100    │
└──────────────────────────┘
```

## 8. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/Networking` | APIClient.streamMessage() 发送流式请求 |
| `Core/PromptEngine` | PromptAssembler.assemble() 拼装 prompt |
| `Core/ContextManager` | ContextManager.prepareHistory() 预处理历史 |
| `Core/Database` | 读写 MessageRecord, ConversationRecord |
| `Features/CharacterCard` | 显示角色卡信息，跳转角色卡详情 |
| `Features/WorldBook` | ChatSettingsSheet 中选择/切换世界书 |
| `Features/Conversation` | ConversationListView 点击进入 ChatView |
| `Features/Settings` | 全局默认参数作为 fallback |

## 9. 设计决策

1. **流式优先**：默认使用流式请求，给用户即时反馈。仅在端点不支持 SSE 时回退到非流式
2. **乐观 UI**：发送消息后立即显示用户气泡和 AI 占位，不等待 API 确认
3. **部分保存**：用户取消生成时保留已生成的内容，而非丢弃
4. **编辑即重新生成**：编辑消息后删除后续消息并重新生成，保持对话逻辑一致性
5. **Token 透明**：显示详细的 token 使用报告，帮助用户理解上下文分配情况

## 实现证据（更新至 2026-05-17）

- 代码位置：
  - `OpenChat/Features/Chat/Views/ChatView.swift` — 主界面 + 记忆更新 banner
  - `OpenChat/Features/Chat/Views/MessageBubbleView.swift` — 气泡 + StatsBarView 集成
  - `OpenChat/Features/Chat/Views/StatsBarView.swift` — 详细/精简统计展示
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` — 状态管理
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` — 流式统计收集、记忆提取、BackgroundManager / PromptAssembler 组装链路
  - `OpenChat/Features/Chat/Models/StreamingStats.swift` — 统计数据模型
  - `OpenChat/Features/Chat/Models/MessageDisplayItem.swift` — DTO（含 streamingStats、contentBlocks、contentRenderRevision）
  - `OpenChat/Shared/Components/MarkdownTextView.swift` — 分块文本渲染、Markdown 延迟刷新与缓存
  - `OpenChat/ContentView.swift`
  - `OpenChat/Core/Background/BackgroundManager.swift`、`BackgroundWorker.swift`、`BackgroundPacket.swift`、`BackgroundAssembler.swift`
  - `OpenChat/Core/PromptEngine/PromptAssembler.swift` — packet-aware preview / assemble overload
- 已完成功能：
  - 聊天主路径：会话读取、消息发送、流式增量展示、数据库持久化
  - 每条 AI 回复下方统计展示（输入/输出 token、TPS、上下文余量 %）
  - 全局设置中「详细统计」开关（关闭时仅在余量 < 20% 显示警告）
  - 流式 API 层支持 `stream_options: {include_usage: true}`，携带 usage 数据
  - 超长流式输出 UI：每个 SSE chunk 仍更新 UI，但 assistant 正文按 block 分段渲染；Markdown parse 按长度 30-100ms lazy 刷新并缓存；上滑/按住暂停滚动跟随，触摸停止 0.5s 后恢复
  - `MemoryExtractionIndicator` 内联显示记忆提取中、已提取和失败状态
  - 发送链路内前置同步记忆提取：按 DB 中 `conversation.lastExtractedSortOrder` 计算待处理消息，达到 4 条后在检索记忆前提取
  - 记忆链路修复：增强 JSON 解析容错、sortOrder cutoff 增量提取、os.Logger 日志、语义检索失败 fallback 到 keyword / high-value 记忆
  - Background Phase 6：Chat 主链路调用 `BackgroundManager.prepare(...)`，再调用 packet-aware `PromptAssembler.preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)`
  - 世界书 bounded rebuild 仍保留在 Chat pre-source stage；`BackgroundWorker` 不触发 rebuild、不写 DB、不联网、不生成 assistant message
- 该模块的核心依赖和 Chat prompt 链路已通过自动化测试验证，其中 `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 锁定当前输入只进入 API request 一次，并验证 packet selected memory/worldBook entries、semantic-only worldBook entry 和 worldBook source failure keyword fallback：
  - `MemoryExtractionParsingTests`（JSON 容错、legacy `latestMemoryDate` 查询、StreamDelta usage）
  - `MemoryExtractionCutoffTests`（sortOrder cutoff、消息不足跳过、并发消息不跳过）
  - `MemoryExtractionPhaseTests`（提取状态模型）
  - `MemoryManagerRetrievalTests`
  - `BackgroundManagerTests` / `BackgroundWorkerTests` / `BackgroundPacketTests` / `BackgroundDiagnosticsTests`
  - `APIClientTests`
  - `PromptAssemblerTests`
  - `TruncationStrategyTests`
  - `StreamingRenderSegmentationTests`（流式文本分块、跨 chunk 换行切分、超长无换行兜底切分、Markdown 刷新延迟策略）
  - `CompressionStrategyTests`
  - `DatabaseManagerMemoryTests`
