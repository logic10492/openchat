# 聊天模块设计

> 所属层：`Features/Chat/`
> 依赖：Core/Networking（APIClient）, Core/PromptEngine, Core/ContextManager, Core/Database, Features/CharacterCard, Features/WorldBook

## 1. 功能范围

- 消息列表展示（支持 Markdown 渲染）
- 流式输出实时显示
- 发送消息 / 停止生成
- 重新生成最后一条 AI 回复
- 编辑已发送的用户消息（编辑后重新生成）
- 当前会话设置（上下文策略、角色卡/世界书切换）
- 会话信息展示（角色卡头像、token 使用情况）
- 每条 AI 回复下方显示详细统计（输入/输出 token 数、TPS、上下文窗口剩余百分比），可在全局设置中关闭详细模式，关闭后仅在窗口余量 < 20% 时显示上下文窗口剩余百分比
- 记忆提取完成时在对话中显示临时提示（"已提取 N 条记忆"，3 秒后自动消失）

> Stage 规划：Chat 当前是单会话/单主角色实现。多角色共同参与、导演 agent 和用户导演输入属于目标 Stage 系统，详见 `arch/modules/stage/index.md`。

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `ChatView.swift` | 聊天主界面，组合消息列表 + 输入栏 + 记忆更新 banner |
| `MessageBubbleView.swift` | 单条消息气泡，支持 Markdown、长按菜单、流式统计展示 |
| `InputBarView.swift` | 底部输入栏（文本框 + 发送/停止按钮） |
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
│ [←] 🎭 艾拉              [⚙️] [📊]    │  ← 导航栏：返回 + 角色头像名称 + 设置 
│─────────────────────────────────────────│
│                                         │
│         [场景：银月森林的入口]           │  ← 场景提示（可选显示）
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 👤 你好，请问你是谁？            │   │  ← 用户消息（右侧）
│  └──────────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 🤖 我是艾拉，银月森林的守护者。  │   │  ← AI 消息（左侧）
│  │ 有什么我能帮助你的吗？           │   │
│  └──────────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 👤 这里是哪里？                  │   │  ← 可编辑：气泡方的铅笔按钮
│  └──────────────────────────────────┘   │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │ 🤖 这里是银月森林的入口...       │   │  ← 可重新生成：长按 → 重新生成
│  │ 前方就是精灵族的领地了。█        │   │  ← 流式输出光标
│  └──────────────────────────────────┘   │
│                                         │
│─────────────────────────────────────────│
│ [输入消息...]                    [■停止]│  ← 生成中显示停止按钮
│ [输入消息...]                    [➤发送]│  ← 空闲时显示发送按钮
└─────────────────────────────────────────┘
```

### 3.2 MessageBubbleView

**布局规则**：
- user 消息：右对齐，主题色背景
- assistant 消息：左对齐，次要色背景
- system 消息：居中，淡灰色，小字体（通常不展示给用户，除非是压缩摘要）

**内容渲染**：
- 使用 Markdown 渲染（粗体、斜体、代码块、列表等）
- 流式输出时逐步追加文本，末尾显示闪烁光标

**长按菜单**：
| 消息类型 | 菜单项 |
|---|---|
| user | 复制、编辑、删除 |
| assistant | 复制、重新生成、删除 |
| system (压缩) | 查看原始内容 |

### 3.3 InputBarView

```swift
struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
}
```

- 多行文本输入框（自动增长高度，最大 5 行）
- 发送按钮：`text` 非空时启用
- 停止按钮：生成中可见，点击取消当前流式请求
- 键盘 Return 不发送（允许换行），需点击按钮发送

### 3.4 ChatSettingsSheet

在聊天界面点击设置图标弹出的 Sheet：

```
┌─────────────────────────────────────────┐
│ 会话设置                         [完成]  │
│─────────────────────────────────────────│
│ Section: 角色与世界                      │
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

    6.5 // 检索记忆
       memories = try await memoryManager.retrieveMemories(
           for: characterCard.id, query: prompt)
       // MemoryManager 内部处理 embedding/model/vector 检索异常，并 fallback 到角色近期记忆。
       // ChatViewModel+Support 只在 fallback 也失败时记录 warning 并继续生成。

    7. 从 DB 读取当前会话消息后，构造 promptHistoryMessages：
       - 乐观保存的当前 user message 保留在 DB/UI 中；
       - prompt history 中排除本轮 current input record；
       - 重新生成/编辑时排除与 currentInput 对应的最后一条 user record。

    8. PromptAssembler.preview(...) 使用 promptHistoryMessages 计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens。

    9. ContextManager.prepareHistory(messages:promptHistoryMessages, ...)
       只处理过滤后的历史，再由 PromptAssembler.assemble(...)
       输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
       tokenUsage = result.tokenUsage

    10. // 创建空的 assistantMessage 占位
        assistantMessage = MessageRecord(role: "assistant", content: "")
        保存到 DB
        追加到 messages 列表

    11. // 流式请求
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
// Then retrieve memories (new extractions immediately available)
memories = try await memoryManager.retrieveMemories(...)
```

- **触发时机**：发送链路内的前置同步提取（位于用户消息持久化之后、记忆检索之前）；`ChatView.onDisappear` 保留 fire-and-forget 调用
- **UI 反馈**：通过 `extractionPhase` 状态驱动 `MemoryExtractionIndicator` 内联指示器，显示"正在提取 / 已提取 N 条 / 提取失败"
- **cutoff 边界**：使用 `conversation.lastExtractedSortOrder`（基于 message sortOrder）替代旧的 `latestMemoryDate`（基于 memory_entry.createdAt），避免并发写入导致消息被跳过
- **错误反馈**：提取失败记录日志并在 UI 显示错误指示器，不阻塞后续生成

## 5. MessageDisplayItem

```swift
struct MessageDisplayItem: Identifiable {
    let id: String
    let role: String
    var content: String           // 可变：流式输出时逐步更新
    let isCompressed: Bool
    let originalContent: String?  // 压缩消息的原始内容
    let createdAt: Date

    init(from record: MessageRecord)
}
```

## 6. 流式输出的 UI 更新策略

### 6.1 节流

流式 SSE 事件频率可能很高（每个 token 一个事件）。为避免 UI 过度刷新：

- 使用 `@Observable` 的属性观察（SwiftUI 自动 diff）
- 累积 delta 到 `content` 字符串，SwiftUI 自动检测变更
- 若仍有性能问题，可引入节流：每 50ms 批量合并 delta 后更新

### 6.2 自动滚动

- 消息列表使用 `ScrollViewReader`
- 新消息到达时 / 流式内容更新时，自动滚动到底部
- 用户手动上滑时暂停自动滚动，出现 "↓ 新消息" 浮动按钮

### 6.3 流式光标

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

## 实现证据（2026-04-16）

- 代码位置：
  - `OpenChat/Features/Chat/Views/ChatView.swift` — 主界面 + 记忆更新 banner
  - `OpenChat/Features/Chat/Views/MessageBubbleView.swift` — 气泡 + StatsBarView 集成
  - `OpenChat/Features/Chat/Views/StatsBarView.swift` — 详细/精简统计展示
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` — 状态管理
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` — 流式统计收集 + 记忆提取
  - `OpenChat/Features/Chat/Models/StreamingStats.swift` — 统计数据模型
  - `OpenChat/Features/Chat/Models/MessageDisplayItem.swift` — DTO（含 streamingStats）
  - `OpenChat/ContentView.swift`
- 已完成功能：
  - 聊天主路径：会话读取、消息发送、流式增量展示、数据库持久化
  - 每条 AI 回复下方统计展示（输入/输出 token、TPS、上下文余量 %）
  - 全局设置中「详细统计」开关（关闭时仅在余量 < 20% 显示警告）
  - 流式 API 层支持 `stream_options: {include_usage: true}`，携带 usage 数据
  - `MemoryExtractionIndicator` 内联显示记忆提取中、已提取和失败状态
  - 发送链路内前置同步记忆提取：按 DB 中 `conversation.lastExtractedSortOrder` 计算待处理消息，达到 4 条后在检索记忆前提取
  - 记忆链路修复：增强 JSON 解析容错、sortOrder cutoff 增量提取、os.Logger 日志、语义检索失败 fallback 到近期记忆
- 该模块的核心依赖和 Chat prompt 链路已通过自动化测试验证，其中 `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 锁定当前输入只进入 API request 一次，并验证语义检索失败时 fallback 记忆仍进入 API request：
  - `MemoryExtractionParsingTests`（JSON 容错、legacy `latestMemoryDate` 查询、StreamDelta usage）
  - `MemoryExtractionCutoffTests`（sortOrder cutoff、消息不足跳过、并发消息不跳过）
  - `MemoryExtractionPhaseTests`（提取状态模型）
  - `MemoryManagerRetrievalTests`
  - `APIClientTests`
  - `PromptAssemblerTests`
  - `TruncationStrategyTests`
  - `CompressionStrategyTests`
  - `DatabaseManagerMemoryTests`
