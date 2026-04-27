# Prompt 拼装引擎设计

> 所属层：`Core/PromptEngine/`
> 依赖：Core/Database（各 Record 类型）, Shared/Extensions（String+Token）

## 1. 功能范围

- 将角色卡、世界书、会话历史、用户输入按规定顺序拼装为完整的 `[ChatMessage]` 数组
- Token 计数与预算分配
- 世界书条目的关键词匹配与动态注入
- 保证拼装结果不超过端点的最大上下文 token 数的 40%（与 ContextManager 协作）

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `PromptAssembler.swift` | 拼装主逻辑，协调各段内容的组装 |
| `PromptSegment.swift` | 定义各段 prompt 的类型与优先级 |
| `TokenCounter.swift` | Token 计数器 |
| `TokenBudget.swift` | 各段 token 预算分配策略 |

## 3. 拼装顺序

最终发送给 API 的 `messages` 数组按以下顺序排列：

```
┌─────────────────────────────────────────────────┐
│  [0] system: 角色卡 system prompt               │  ← 固定段
│      (未设置时使用默认模板)                       │
├─────────────────────────────────────────────────┤
│  [1] system: 世界书条目 (position=after_system)  │  ← 动态段
│      (按 priority 降序，关键词命中的条目)         │
├─────────────────────────────────────────────────┤
│  [2] system: 角色描述                            │  ← 固定段
│      (personality + appearance + physique +       │
│       speechStyle + backstory 拼接)              │
├─────────────────────────────────────────────────┤
│  [3] system: 场景设定                            │  ← 固定段
│      (会话 customScenario ?? 角色卡 scenario)    │
├─────────────────────────────────────────────────┤
│  [4] system: 慢速剧情推进指令 (beta)             │  ← 条件段
│      (仅 conversation.slowPlotMode=true 时注入)  │
├─────────────────────────────────────────────────┤
│  [5] system: 时间上下文                          │  ← 固定段（始终注入）
│      [Time] ISO 8601 当前时间含时区 [/Time]      │
├─────────────────────────────────────────────────┤
│  [6] system: 世界书条目 (position=before_history)│  ← 动态段
├─────────────────────────────────────────────────┤
│  [7] system: 跨对话记忆                          │  ← 动态段
│      (经语义检索匹配的记忆条目，按相关度排序)  │
├─────────────────────────────────────────────────┤
│  [8..N-2] 示例对话                               │  ← 可选段
│      (user/assistant 交替)                       │
├─────────────────────────────────────────────────┤
│  [N-1..M-1] 会话历史                             │  ← 动态段
│      (经 ContextManager 处理后的最近消息)         │
├─────────────────────────────────────────────────┤
│  [M] user: 当前用户输入                          │  ← 固定段
└─────────────────────────────────────────────────┘
```

### 默认 system prompt 模板

当角色卡未设置 `systemPrompt` 时使用：

```
You are {{charName}}, engaging in a roleplay conversation.
Stay in character at all times. Respond naturally as {{charName}} would.
```

### 角色描述拼接规则

将角色卡中非空的描述字段按以下模板拼接为一条 system 消息：

```
[Character: {{charName}}]
Personality: {{personality}}
Appearance: {{appearance}}
Physique: {{physique}}
Speech style: {{speechStyle}}
Backstory: {{backstory}}
```

空字段跳过对应行。

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

    // 固定段：按实际占用计算，不可压缩
    var systemPromptTokens: Int       // 实际计数
    var characterDescTokens: Int      // 实际计数
    var scenarioTokens: Int           // 实际计数
    var currentInputTokens: Int       // 实际计数

    // 可选段：有预算上限
    var exampleDialogsMaxTokens: Int  // 上限 = remaining * 25%
    var worldBookMaxTokens: Int       // 上限 = remaining * 35%
    var memoryMaxTokens: Int          // 上限 = remaining * 15%

    // 动态段：弹性填充剩余空间
    var historyMaxTokens: Int         // = totalBudget - 所有固定段 - 可选段实际占用

    /// 计算各段实际可用预算
    static func calculate(
        totalBudget: Int,
        fixedSegments: [PromptSegment],     // 已计算 token 的固定段
        exampleDialogs: [ChatMessage],
        triggeredEntries: [WorldBookEntryRecord]
    ) -> TokenBudget
}
```

### 4.3 预算分配流程

```
1. 计算固定段总 token：systemPrompt + charDesc + scenario + slowPlotDirective(条件) + timeContext + currentInput
2. 剩余预算 = totalBudget - 固定段总 token
3. 分配示例对话预算 = min(剩余 * 0.25, 示例对话实际 token)
4. 分配世界书预算 = min(剩余 * 0.35, 触发条目总 token)
5. 分配记忆预算 = min(剩余 * 0.15, 记忆条目总 token)
6. 历史预算 = 剩余 - 示例对话实际占用 - 世界书实际占用 - 记忆实际占用
7. 若历史预算 < 某阈值（如 200 token），压缩/丢弃示例对话以腾出空间
```

## 5. 核心接口

### 5.1 PromptAssembler

```swift
struct PromptAssembler {
    /// 拼装完整的 messages 数组
    /// - conversation: 当前会话记录
    /// - characterCard: 绑定的角色卡（可选）
    /// - worldBook: 绑定的世界书（可选）
    /// - recentMessages: 经 ContextManager 处理后的历史消息
    /// - currentInput: 用户当前输入
    /// - endpoint: API 端点配置（提供 maxContextTokens）
    /// - returns: 拼装好的 ChatMessage 数组 + token 使用统计
    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult
}

struct AssemblyResult {
    let messages: [ChatMessage]          // 最终发送给 API 的消息数组
    let tokenUsage: TokenUsageReport     // token 使用统计
    let triggeredEntries: [String]       // 被触发的世界书条目 ID（用于调试展示）
}

struct TokenUsageReport {
    let totalBudget: Int
    let systemPrompt: Int
    let characterDescription: Int
    let scenario: Int
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
    case timeContext(String)                    // ISO 8601 时间上下文（始终注入）
    case worldBookEntry(WorldBookEntryRecord)
    case memoryEntry(MemoryEntryRecord)         // 跨对话记忆
    case exampleDialog(ChatMessage)
    case historyMessage(MessageRecord)
    case currentInput(String)

    var role: String           // system / user / assistant
    var content: String
    var tokenCount: Int        // 缓存的 token 计数
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
| `timeContext` | system | .max | true | 由 PromptAssembler 内部 `Date()` → ISO 8601 生成，格式 `[Time] ... [/Time]`，~15 tokens |
| `worldBookEntry` | system | entry.priority | false | |
| `memoryEntry` | system | 85 | false | 高于 exampleDialog(75)，低于世界书条目最大值 |
| `exampleDialog` | user/assistant | 75 | false | |
| `historyMessage` | user/assistant | 50 | false | |
| `currentInput` | user | .max | true | |
```

### 5.3 TokenCounter

```swift
struct TokenCounter {
    /// 估算文本的 token 数
    /// 使用简易算法：英文按空格分词，中/日/韩按字符计数，每个 token ≈ 4 字符（英文）或 1-2 字符（CJK）
    static func count(_ text: String) -> Int

    /// 估算一条 ChatMessage 的 token 数（含 role 标记的固定开销）
    static func count(message: ChatMessage) -> Int
}
```

**Token 估算算法**：

```
对于文本中的每个字符：
  - ASCII 字母/数字/空格：累积，每 4 个字符算 1 token
  - CJK 字符（Unicode range 0x4E00-0x9FFF 等）：每个字符算 1.5 token
  - 其他（标点、特殊符号）：每个算 1 token
每条消息额外 +4 token（role 标记开销）
```

> 注：这是近似算法。若需精确计数，可后续集成 tiktoken 的 Swift 移植版本。

## 6. 拼装流程伪代码

```
function assemble(conversation, characterCard, worldBook, entries, memories, history, input, endpoint):
    totalBudget = endpoint.maxContextTokens * 0.40
    segments = []

    // 1. System prompt
    sysPrompt = characterCard?.systemPrompt ?? defaultTemplate(characterCard?.name)
    segments.append(.systemPrompt(sysPrompt))

    // 2. 世界书条目 (after_system)
    contextText = concatText(history.last(5), input)
    triggeredEntries = entries
        .filter { $0.isEnabled && $0.position == "after_system" }
        .filter { KeywordMatcher.isTriggered($0, contextText) }
        .sorted { $0.priority > $1.priority }
    for entry in triggeredEntries:
        segments.append(.worldBookEntry(entry))

    // 3. 角色描述
    if let card = characterCard:
        desc = buildCharacterDescription(card)
        if !desc.isEmpty:
            segments.append(.characterDescription(desc))

    // 4. 场景设定
    scenario = conversation.customScenario ?? characterCard?.scenario
    if let s = scenario, !s.isEmpty:
        segments.append(.scenario(s))

    // 4.5 慢速剧情推进指令（beta，会话级可关闭）
    if conversation.slowPlotMode:
        segments.append(.slowPlotDirective(AppConstants.slowPlotModePrompt))

    // 5. 时间上下文（始终注入）
    timeString = ISO8601DateFormatter().string(from: Date())
    segments.append(.timeContext("[Time] \(timeString) [/Time]"))

    // 6. 世界书条目 (before_history)
    triggeredBeforeHistory = entries
        .filter { $0.isEnabled && $0.position == "before_history" }
        .filter { KeywordMatcher.isTriggered($0, contextText) }
        .sorted { $0.priority > $1.priority }
    for entry in triggeredBeforeHistory:
        segments.append(.worldBookEntry(entry))

    // 7. 跨对话记忆
    for memory in memories:
        segments.append(.memoryEntry(memory))

    // 8. 示例对话
    if let examples = characterCard?.exampleDialogs:
        for msg in parseExampleDialogs(examples):
            segments.append(.exampleDialog(msg))

    // 9. 计算 token 预算
    budget = TokenBudget.calculate(totalBudget, segments, ...)

    // 10. 历史消息（从最近到最远，直到预算耗尽）
    remainingTokens = budget.historyMaxTokens
    for msg in history.reversed():
        tokens = TokenCounter.count(msg)
        if remainingTokens - tokens < 0: break
        segments.insert(.historyMessage(msg), atCorrectPosition)
        remainingTokens -= tokens

    // 11. 当前用户输入
    segments.append(.currentInput(input))

    // 12. 裁剪超预算的世界书/记忆/示例对话
    trimOverBudgetSegments(segments, budget)

    // 13. 转换为 [ChatMessage]
    return segments.map { $0.toChatMessage() }
```

## 7. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/Database` | 读取 CharacterCardRecord、WorldBookEntryRecord、MemoryEntryRecord、ConversationRecord |
| `Core/ContextManager` | ContextManager 先处理历史消息（剔除/压缩），再传入 PromptAssembler |
| `Core/Memory` | MemoryManager 检索记忆后传入 PromptAssembler |
| `Features/Chat` | ChatViewModel 在发送消息时调用 PromptAssembler.assemble() |
| `Shared/Extensions` | 使用 String+Token 扩展的 token 计数方法 |

## 8. 设计决策

1. **40% 上下文预算**：参考用户需求，控制在 40% 以内以保持小模型对当前对话的专注度
2. **动态世界书注入**：不全量注入世界书，仅注入关键词命中的条目，节省 token
3. **近似 token 计数**：避免引入重型依赖（tiktoken），用近似算法覆盖 90%+ 场景。CJK 文本的误差通过预留余量吸收
4. **预算分配弹性**：历史消息获得最大弹性空间，因为对话质量主要取决于近期上下文
5. **可选段可裁剪**：当 token 紧张时，示例对话优先被裁剪，因为其作用是引导风格而非提供关键信息
6. **慢速剧情推进模式（beta）**：作为条件固定段注入，默认开启，会话级可关闭。提示词内容固定存储于 AppConstants，不可用户编辑。isRequired=false 但 priority=.max（开启时不被裁剪）

## 实现证据（2026-04-14，更新于 2026-04-27）

- 代码位置：
  - `OpenChat/Core/PromptEngine/PromptAssembler.swift` — `makeTimeContext()` 输出 `[Time] <ISO8601> [/Time]`；`before_history` 世界书条目位于 memory 前。
  - `OpenChat/Core/PromptEngine/KeywordMatcher.swift`
  - `OpenChat/Core/PromptEngine/TokenCounter.swift`
  - `OpenChat/Core/PromptEngine/TokenBudget.swift`
  - `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift` — TokenUsageReport 含 slowPlotDirective 字段
  - `OpenChat/App/AppConstants.swift` — slowPlotModePrompt 常量
  - `OpenChat/Core/Database/Records/ConversationRecord.swift` — slowPlotMode 字段
  - `OpenChat/Core/Database/Migrations.swift` — v7_add_slow_plot_mode 迁移
- 已验证测试：
  - `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`（含慢速模式开/关/token 预算测试；覆盖 ISO8601 时间格式、memory 注入、`before_history -> memory -> exampleDialogs` 相对顺序）
  - `OpenChatTests/Core/PromptEngineTests/KeywordMatcherTests.swift`
  - `OpenChatTests/Core/PromptEngineTests/TokenCounterTests.swift`
- 当前实现已具备角色卡字段注入、世界书关键词触发、固定段预估与历史预算协作的基础能力，可支撑聊天主链路运行
