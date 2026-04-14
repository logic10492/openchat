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

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `ChatView.swift` | 聊天主界面，组合消息列表 + 输入栏 |
| `MessageBubbleView.swift` | 单条消息气泡，支持 Markdown、长按菜单 |
| `InputBarView.swift` | 底部输入栏（文本框 + 发送/停止按钮） |
| `ChatSettingsSheet.swift` | 当前会话设置面板 |
| `ChatViewModel.swift` | 核心 ViewModel，管理消息状态、调度 API 请求 |
| `MessageDisplayItem.swift` | 消息展示用 DTO |

## 3. 视图设计

### 3.1 ChatView（主界面）

```
┌─────────────────────────────────────────┐
│ [←] 🎭 艾拉              [⚙️] [📊]    │  ← 导航栏：返回 + 角色头像名称 + 设置 + token统计
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
│  │ 👤 这里是哪里？                  │   │  ← 可编辑：长按 → 编辑
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
│   世界书: [中土世界 ▸]      [更换/移除] │
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
       worldBook = 从 DB 加载 conversation.worldBookId
       worldBookEntries = 从 DB 加载世界书的已启用条目
       endpoint = 从 DB 加载 conversation.apiEndpointId

    7. // 阶段1：计算固定段 token
       fixedTokens = PromptAssembler.calculateFixedTokens(
           characterCard, worldBookEntries, currentInput, ...)

    8. // 阶段2：上下文管理
       processedHistory = await contextManager.prepareHistory(
           conversation, endpoint, fixedTokens)

    9. // 阶段3：拼装 prompt
       result = PromptAssembler.assemble(
           conversation, characterCard, worldBook, worldBookEntries,
           processedHistory, inputText, endpoint)
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

## 实现证据（2026-04-14）

- 代码位置：
  - `OpenChat/Features/Chat/ChatView.swift`
  - `OpenChat/Features/Chat/ChatViewModel.swift`
  - `OpenChat/Features/Chat/ChatViewModel+Support.swift`
  - `OpenChat/ContentView.swift`
- 当前已完成聊天主路径的装配：会话读取、消息发送、流式增量展示、数据库持久化、PromptAssembler/ContextManager 接线
- 该模块的核心依赖已通过自动化测试间接验证：
  - `APIClientTests`
  - `PromptAssemblerTests`
  - `TruncationStrategyTests`
  - `CompressionStrategyTests`
