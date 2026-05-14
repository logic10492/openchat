# Prompt 拼装引擎设计

> 所属层：`Core/PromptEngine/`
> 依赖：`Core/Database`（各 Record 类型）、`Core/Networking`（`ChatMessage` / `APIEndpointConfig`）、`Core/ContextManager`（运行时历史处理）

## 1. 功能范围

- 将角色卡、世界书、会话历史、用户输入按规定顺序拼装为完整的 `[ChatMessage]` 数组
- Token 计数与预算分配
- 世界书条目的关键词匹配与动态注入
- 以端点最大上下文 token 数的 40% 作为 prompt 预算目标，并与 ContextManager 协作控制历史窗口

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `PromptAssembler.swift` | 拼装主逻辑，协调各段内容的组装 |
| `PromptAssemblyModels.swift` | 定义 `PromptAssemblyPreview`、`AssemblyResult`、`TokenUsageReport` |
| `PromptSegment.swift` | 定义各段 prompt 的类型与优先级 |
| `KeywordMatcher.swift` | 世界书关键词匹配与优先级排序 |
| `TokenCounter.swift` | Token 计数器 |
| `TokenBudget.swift` | 各段 token 预算分配策略 |

## 3. 拼装顺序

最终发送给 API 的 `messages` 数组按以下四层顺序排列。

|  顺序 | 分层                        | role             | 段名                                | 来源 / 条件                                                                        | 性质  | 备注                                                             |
| --: | ------------------------- | ---------------- | --------------------------------- | ------------------------------------------------------------------------------ | --- | -------------------------------------------------------------- |
|   0 | Stable Identity           | system           | base system prompt                | `characterCard.systemPrompt`，未设置时使用默认模板                                        | 固定段 | 始终在最前                                                          |
|   1 | Stable Identity           | system           | character description             | `personality` / `appearance` / `physique` / `speechStyle` / `backstory` 非空字段拼接 | 固定段 | 空字段跳过                                                          |
|   2 | Stable Identity           | system           | scenario                          | `conversation.customScenario ?? characterCard.scenario`                        | 固定段 | 两者都为空则跳过                                                       |
|   3 | Stable Identity           | system           | slowPlot directive                | `conversation.slowPlotMode == true`                                            | 条件段 | beta；默认开启                                                      |
|   4 | Stable Conversation State | system           | compressed context                | `ContextManager` compression checkpoint summary                                | 动态段 | 无 checkpoint summary 时跳过                                       |
|   5 | Stable Conversation State | user / assistant | checkpoint 后会话历史                  | `ContextManager` 返回的 checkpoint 后 `processedHistory`                           | 动态段 | 不包含本轮当前输入                                                      |
|   6 | Current-Turn Context      | system           | example dialogs block             | `characterCard.exampleDialogs`                                                 | 可选段 | 以带标签的 system block 注入，不再作为原始 user/assistant 示例消息注入             |
|   7 | Current-Turn Context      | system           | world book entries block          | 当前输入 + 最近历史触发的世界书条目                                                            | 动态段 | 按 `priority` 降序；目标顺序不再暴露 `after_system` / `before_history` 注入点 |
|   8 | Current-Turn Context      | system           | memories block                    | `MemoryManager.retrieveMemories(...)` 按当前输入检索返回的记忆                             | 动态段 | 按检索结果顺序和 token 预算裁剪；不按 `importance` 重排                       |
|   9 | Current Turn              | user             | current user input + time context | `currentInput` + `PromptAssembler.makeTimeContext()`                           | 固定段 | 同一条 user message 内先放用户输入，再放 `[Time] <ISO8601> [/Time]`         |

旧的 `WorldBookEntryPosition.after_system` / `.before_history` 字段保留为既有数据兼容字段，不再决定最终 prompt 位置。所有当前轮命中的世界书内容最终统一落入 Current-Turn Context 的 world book block。

### 默认 system prompt 模板

当角色卡未设置 `systemPrompt` 时使用：

```
You are {{charName}}, engaging in a roleplay conversation. Stay in character at all times. Respond naturally as {{charName}} would.
```

当前 `PromptAssembler` 在内部生成该默认值；当角色名为空时使用 `the character`。`AppConstants.defaultSystemPrompt(...)` 存在，但当前 prompt 主链路未调用它。

### 角色描述拼接规则

将角色卡中非空的描述字段按以下模板拼接为一条 system 消息：

```
Character: {{charName}}
Personality: {{personality}}
Appearance: {{appearance}}
Physique: {{physique}}
Speech style: {{speechStyle}}
Backstory: {{backstory}}
```

空字段跳过对应行。

### 示例对话 block 规则

角色卡中的 `exampleDialogs` 需要转换为一条带标签的 system 消息，而不是拆成原始 `user` / `assistant` 消息：

```
[Example Dialogs]
User: {{example user message}}
Assistant: {{example assistant message}}
[/Example Dialogs]
```

该 block 的作用是提供当前轮风格参考，因此位于 Stable Conversation State 之后、Current Turn 之前。

## 4. Token 预算分配

### 4.1 总预算

```
totalBudget = endpoint.maxContextTokens * 0.40
```

即上下文窗口的 40%。剩余 60% 保留给模型生成和安全余量。

### 4.2 各段预算分配

使用 **固定段优先、动态段弹性** 的分配策略：

```swift
struct TokenBudget {
    let totalBudget: Int
    let fixedTokens: Int
    let exampleDialogsBudget: Int
    let worldBookBudget: Int
    let memoryBudget: Int
    let historyBudget: Int

    /// 计算各段实际可用预算
    static func calculate(
        totalBudget: Int,
        fixedTokens: Int,
        exampleDialogsTokens: Int,
        worldBookTokens: Int,
        memoryTokens: Int = 0
    ) -> TokenBudget
}
```

### 4.3 预算分配流程

```
1. 计算不可裁剪固定段 token：Stable Identity + Current Turn（currentInput + timeContext）
2. 剩余预算 = totalBudget - 固定段总 token
3. 分配示例对话预算 = min(剩余 * 0.25, 示例对话实际 token)
4. 分配世界书预算 = min(剩余 * 0.35, 触发条目总 token)
5. 分配记忆预算 = min(剩余 * 0.15, 记忆条目总 token)
6. `preview(...)` 按预算分别裁剪 example dialogs、world book entries、memories；每类至少允许保留第一条命中项，即第一条可能单独超过该类预算
7. 重新计算 `actualFixedTokens = stableIdentityMessages + currentTurnContextMessages + currentTurnMessage`
8. `historyBudget = max(totalBudget - actualFixedTokens, 0)`；最终 compressed context / checkpoint 后历史由 `ContextManager` 执行
```

> 说明：`fixedTokens` 不再表示“全部位于 history 之前的消息”，而是表示除 Stable Conversation State 外不可被 ContextManager 裁剪的 token 总量。`ContextManager` 仍根据该值计算历史窗口，`assemble(...)` 再把 Stable Conversation State 放回 Stable Identity 与 Current-Turn Context 之间。

## 5. 核心接口

### 5.1 PromptAssembler

```swift
struct PromptAssembler {
    /// 预计算 Stable Identity、Current-Turn Context、Current Turn、fixedTokens 与 historyBudget。
    /// ChatViewModel 会先用该结果调用 ContextManager 处理历史消息。
    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        recentMessages: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview

    /// 拼装完整的 messages 数组
    /// - conversation: 当前会话记录
    /// - characterCard: 绑定的角色卡（可选）
    /// - worldBook: 绑定的世界书（可选）
    /// - recentMessages: 用于世界书关键词触发和 preview 预算的候选历史；不包含本轮当前输入
    /// - processedHistory: ContextManager 返回的剔除/压缩后历史
    /// - currentInput: 用户当前输入
    /// - endpoint: API 端点配置（提供 maxContextTokens）
    /// - returns: 拼装好的 ChatMessage 数组 + token 使用统计
    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        recentMessages: [MessageRecord],
        processedHistory: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult
}

struct PromptAssemblyPreview: Sendable {
    let stableIdentityMessages: [ChatMessage]
    let currentTurnContextMessages: [ChatMessage]
    let currentTurnMessage: ChatMessage
    let fixedTokens: Int
    let historyBudget: Int
    let tokenUsage: TokenUsageReport
    let triggeredEntries: [String]
}

struct AssemblyResult: Sendable {
    let messages: [ChatMessage]          // 最终发送给 API 的消息数组
    let tokenUsage: TokenUsageReport     // token 使用统计
    let triggeredEntries: [String]       // 被触发的世界书条目 ID（用于调试展示）
}

struct TokenUsageReport: Sendable {
    let totalBudget: Int
    let systemPrompt: Int
    let characterDescription: Int
    let scenario: Int
    let slowPlotDirective: Int
    let timeContext: Int
    let worldBookEntries: Int
    let memories: Int
    let exampleDialogs: Int
    let history: Int
    let currentInput: Int
    let totalUsed: Int
    let remaining: Int
}
```

### 5.2 PromptSegment

```swift
enum PromptSegment {
    case systemPrompt(String)
    case characterDescription(String)
    case scenario(String)
    case slowPlotDirective(String)             // 慢速剧情推进指令（beta，会话级可关闭）
    case worldBookEntry(WorldBookEntryRecord)
    case memoryEntry(MemoryEntryRecord)         // 跨对话记忆
    case exampleDialogsBlock(String)            // 示例对话以 labeled system block 注入
    case historyMessage(MessageRecord)
    case currentTurn(String)                    // 当前用户输入 + ISO 8601 时间上下文

    var role: String           // system / user / assistant
    var content: String
    var tokenCount: Int        // 按 segment.content 估算，不含 ChatMessage role 开销
    var priority: Int          // 用于预算紧张时的裁剪优先级
    var isRequired: Bool       // 是否不可省略
}
```

**各 case 属性**：

| case | role | priority | isRequired | 说明 |
|---|---|---|---|---|
| `systemPrompt` | system | .max | true | |
| `characterDescription` | system | .max | false | |
| `scenario` | system | .max | false | |
| `slowPlotDirective` | system | .max | false | 仅 conversation.slowPlotMode=true 时注入，内容定义于 AppConstants |
| `worldBookEntry` | system | entry.priority | false | 当前轮统一注入到 world book block |
| `memoryEntry` | system | 85 | false | 高于 exampleDialogsBlock(75)，低于世界书条目最大值 |
| `exampleDialogsBlock` | system | 75 | false | labeled block，不再拆成 user/assistant |
| `historyMessage` | user/assistant | 50 | false | |
| `currentTurn` | user | .max | true | 当前用户输入在前，`[Time] ... [/Time]` 在后 |
```

> 注意：`PromptSegment.worldBookEntry.content` / `memoryEntry.content` 返回原始正文；当前实际发送内容由 `PromptAssembler.makeWorldBookMessageContent(...)` 与 `makeMemoryMessageContent(...)` 包装为 `[World Book: title]`、`[Memory — type]` 形式。

### 5.3 TokenCounter

```swift
struct TokenCounter {
    /// 估算文本的 token 数
    /// 使用简易算法：英文按空格分词，中/日/韩按字符计数，每个 token ≈ 4 字符（英文）或 1-2 字符（CJK）
    static func count(_ text: String) -> Int

    /// 估算一条 ChatMessage 的 token 数（含 role 标记的固定开销）
    static func count(message: ChatMessage) -> Int

    /// 估算一条 MessageRecord 的 token 数（含 role 标记的固定开销）
    static func count(message: MessageRecord) -> Int
}
```

**Token 估算算法**：

```
对于文本中的每个字符：
  - ASCII 字母/数字/空格/制表/换行：累积，每 4 个字符算 1 token
  - CJK 字符（0x4E00-0x9FFF、0x3040-0x30FF、0xAC00-0xD7AF）：每个字符算 1.5 token
  - 其他（标点、特殊符号）：每个算 1 token
每条消息额外 +4 token（role 标记开销）
```

> 注：这是近似算法。若需精确计数，可后续集成 tiktoken 的 Swift 移植版本。

## 6. 拼装流程伪代码

```
function preview(conversation, characterCard, worldBook, entries, memories, history, input, endpoint):
    totalBudget = endpoint.maxContextTokens * 0.40

    // 1. Stable Identity
    sysPrompt = characterCard?.systemPrompt ?? defaultTemplate(characterCard?.name)
    systemMessage = ChatMessage(role: "system", content: sysPrompt)

    if let card = characterCard:
        desc = buildCharacterDescription(card)
        if !desc.isEmpty:
            characterMessage = ChatMessage(role: "system", content: desc)

    scenario = conversation.customScenario ?? characterCard?.scenario
    if let s = scenario, !s.isEmpty:
        scenarioMessage = ChatMessage(role: "system", content: s)

    if conversation.slowPlotMode:
        slowPlotMessage = ChatMessage(role: "system", content: AppConstants.slowPlotModePrompt)

    stableIdentityMessages =
        [systemMessage]
        + optional(characterMessage)
        + optional(scenarioMessage)
        + optional(slowPlotMessage)

    // 2. Current-Turn Context 候选
    contextText = concatText(history.suffix(5), input)
    triggeredWorldBookEntries = entries
        .filter { $0.isEnabled }
        .filter { KeywordMatcher.isTriggered($0, contextText) }
        .sorted { $0.priority > $1.priority }

    exampleDialogBlock = makeExampleDialogsBlock(characterCard.exampleDialogMessages())
    worldBookBlock = makeWorldBookBlock(triggeredWorldBookEntries)
    memoryBlock = makeMemoryBlock(memories) // preserve retrieval order

    // 3. Current Turn
    timeString = ISO8601DateFormatter().string(from: Date())
    currentTurnMessage = ChatMessage(
        role: "user",
        content: input + "\n\n[Time] \(timeString) [/Time]"
    )

    // 4. TokenBudget 只负责给 Current-Turn Context 与 Stable Conversation State 分配上限
    baseFixedTokens = tokenCount(stableIdentityMessages) + tokenCount(currentTurnMessage)
    exampleTokens = tokenCount(exampleDialogBlock)
    worldBookTokens = tokenCount(worldBookBlock)
    memoryTokens = tokenCount(memoryBlock)
    budget = TokenBudget.calculate(totalBudget, baseFixedTokens, exampleTokens, worldBookTokens, memoryTokens)
    trimmedExampleDialogBlock = trim(exampleDialogBlock, budget.exampleDialogsBudget)
    trimmedWorldBookBlock = trim(worldBookBlock, budget.worldBookBudget)
    trimmedMemoryBlock = trim(memoryBlock, budget.memoryBudget)

    currentTurnContextMessages =
        optional(trimmedExampleDialogBlock)
        + optional(trimmedWorldBookBlock)
        + optional(trimmedMemoryBlock)

    actualFixedTokens =
        tokenCount(stableIdentityMessages)
        + tokenCount(currentTurnContextMessages)
        + tokenCount(currentTurnMessage)
    return PromptAssemblyPreview(
        stableIdentityMessages,
        currentTurnContextMessages,
        currentTurnMessage,
        actualFixedTokens,
        max(totalBudget - actualFixedTokens, 0)
    )

function assemble(..., processedHistory, input):
    context = preview(...)
    messages = context.stableIdentityMessages
    messages += processedHistory.map(\.chatMessage)
    messages += context.currentTurnContextMessages
    messages.append(context.currentTurnMessage)
    return AssemblyResult(messages, finalTokenUsage, context.triggeredEntries)
```

实际发送链路由 `ChatViewModel+Support.generateResponse(...)` 串联：

1. 若 `sendMessage()` 本轮会持久化用户消息，先保存 user record，再读取 DB 中当前会话消息。
2. `makePromptHistoryMessages(...)` 从历史候选中移除本轮 user record；重新生成/编辑等不持久化入口会按最后一条同内容 user 消息做兜底过滤。
3. `MemoryManager.retrieveMemories(for:query:limit:)` 按当前输入检索角色相关记忆；若语义检索失败，`MemoryManager` 内部会 fallback 到角色近期记忆，外层失败则记录 warning 并继续空 memory。
4. `PromptAssembler.preview(...)` 使用过滤后的 `promptHistoryMessages` 与 `currentInput` 计算 Current-Turn Context、Current Turn、`fixedTokens` 和初始 token usage。
5. `ContextManager.prepareHistory(messages:conversation:endpoint:fixedTokens:)` 只处理过滤后的历史；truncation 返回尾部历史，compression 返回 `[Previously]` checkpoint summary + checkpoint 后历史。
6. `PromptAssembler.assemble(... processedHistory: ...)` 再次调用 `preview(...)` 得到同一类上下文，拼接 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`，并更新最终 `TokenUsageReport`。

## 7. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/Database` | 读取 CharacterCardRecord、WorldBookEntryRecord、MemoryEntryRecord、ConversationRecord |
| `Core/ContextManager` | PromptAssembler.preview 先计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens；ContextManager 据此处理历史消息（剔除/压缩）；PromptAssembler.assemble 接收 processedHistory |
| `Core/Memory` | MemoryManager 检索记忆后传入 PromptAssembler |
| `Features/Chat` | ChatViewModel 在发送消息时调用 `PromptAssembler.preview(...)` 和 `PromptAssembler.assemble(...)` |
| `Shared/Extensions` | `String.approximatedTokenCount` 委托 `TokenCounter.count(_:)`，供其他层复用同一估算 |

## 8. 设计决策

1. **40% 上下文预算**：参考用户需求，控制在 40% 以内以保持小模型对当前对话的专注度
2. **四层顺序稳定**：先放 Stable Identity，再放 Stable Conversation State，再放 Current-Turn Context，最后放 Current Turn，避免当前轮检索信息打断角色身份或历史连续性
3. **动态世界书注入**：不全量注入世界书，仅注入当前输入 + 最近历史关键词命中的条目，节省 token
4. **示例对话降级为 labeled system block**：示例对话只表达风格参考，不再伪装成真实 user/assistant 历史，避免污染会话状态
5. **近似 token 计数**：避免引入重型依赖（tiktoken），用近似算法覆盖 90%+ 场景。CJK 文本的误差通过预留余量吸收
6. **预算分配弹性**：历史消息获得最大弹性空间，因为对话质量主要取决于近期上下文
7. **可选段可裁剪**：当 token 紧张时，示例对话优先被裁剪，因为其作用是引导风格而非提供关键信息
8. **慢速剧情推进模式（beta）**：作为条件固定段注入，默认开启，会话级可关闭。提示词内容固定存储于 AppConstants，不可用户编辑。isRequired=false 但 priority=.max（开启时不被裁剪）

## 当前实现证据（更新于 2026-04-30）

- 代码位置：
  - `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift` — `PromptAssemblyPreview` 输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
  - `OpenChat/Core/PromptEngine/PromptAssembler.swift` — `preview(...)` 计算四层结构、`fixedTokens` / `historyBudget`；`assemble(...)` 输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
  - `OpenChat/Core/PromptEngine/PromptSegment.swift` — 使用 `.exampleDialogsBlock(String)` 与 `.currentTurn(String)` 表达目标语义；time context 不再是独立 segment。
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` — `generateResponse(...)` 串联 `preview -> prepareHistory -> assemble`，并通过 `makePromptHistoryMessages(...)` 过滤本轮 user record，避免当前输入在历史和末尾 user 消息中重复。
  - `OpenChat/Core/PromptEngine/KeywordMatcher.swift`
  - `OpenChat/Core/PromptEngine/TokenCounter.swift`
  - `OpenChat/Core/PromptEngine/TokenBudget.swift`
  - `OpenChat/App/AppConstants.swift` — slowPlotModePrompt 常量
  - `OpenChat/Core/Database/Records/ConversationRecord.swift` — slowPlotMode 字段
  - `OpenChat/Core/Database/Migrations.swift` — v7_add_slow_plot_mode 迁移
  - `OpenChat/Core/ContextManager/PreparedHistory.swift` — compression checkpoint 通过 `[Previously]` system message 进入 Stable Conversation State。
- 已验证测试：
  - `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`（含慢速模式开/关/token 预算测试；覆盖四层顺序、preview 四层输出、labeled example/world book/memory blocks、世界书 position 兼容、current turn 内时间上下文）
  - `OpenChatTests/Core/PromptEngineTests/KeywordMatcherTests.swift`
  - `OpenChatTests/Core/PromptEngineTests/TokenCounterTests.swift`
  - `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`（覆盖真实发送链路中当前输入只发送一次、API request 四层顺序、memory fallback 注入、checkpoint invalidation、compression mode 持久化）
  - `OpenChatTests/Core/ContextManagerTests/CompressionCheckpointReuseTests.swift`
- 当前实现描述：
  - 世界书触发上下文使用 `recentMessages.suffix(5) + currentInput`，其中 `recentMessages` 应排除本轮当前输入。
  - 示例对话以 `[Example Dialogs]` labeled system block 注入，位于 Stable Conversation State 之后。
  - 世界书条目统一进入 `[World Book Entries]` block，不再按 `after_system` / `before_history` 拆分最终位置。
  - 记忆条目统一进入 `[Memories]` block，位于 world book block 之后。
  - 时间上下文位于最后一条 current turn user message 内，用户输入在前，`[Time] <ISO8601> [/Time]` 在后。
  - `assemble(...)` 只接收 ContextManager 已处理的 `processedHistory`，不会自行截断或压缩历史。
- 验证记录：
  - `harness/2026.04.30/checkpoint-compression/evidence.txt`
  - `arch/AntiEntropy/triangle-consistency.md#checkpoint-compression-三边一致性写回2026-04-30`
  - 2026-04-30 focused prompt suite：`PromptAssemblerTests` 13 tests passed。
  - 2026-04-30 focused chat prompt suite：`ChatViewModelPromptAssemblyTests` 9 tests passed。
