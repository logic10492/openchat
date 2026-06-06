# Prompt 拼装引擎设计

> 所属层：`Core/PromptEngine/`
> 依赖：`Core/Database`（各 Record 类型）、`Core/Networking`（`ChatMessage` / `APIEndpointConfig`）、`Core/ContextManager`（运行时历史处理）、`Core/Background`（packet-compatible prompt items）

## 1. 功能范围

- 将角色卡、世界书、会话历史、用户输入按规定顺序拼装为完整的 `[ChatMessage]` 数组
- Token 计数与预算分配
- 世界书 / 记忆条目的动态注入；Chat 主链路消费 `BackgroundPacket`，旧 direct overload 保留关键词 fallback / rollback
- 以端点最大上下文 token 数的 40% 作为 prompt 预算目标，并与 ContextManager 协作控制历史窗口

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `PromptAssembler.swift` | 拼装主逻辑，协调各段内容的组装；当前主链路使用 packet-aware overload |
| `../Background/BackgroundAssembler.swift` | 将 `BackgroundPacket` 分组为兼容 `[World Book Entries]` / `[Memories]` prompt items |
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
|   2 | Stable Identity           | system           | role skill block                  | `RoleSkillPromptMaterial`，由 Chat runtime 从 `character_skill_bundle` 读取完整 `SKILL.md` | 条件段 | 以 `[Role Skill] <role_skill> ... </role_skill>` 注入；本阶段不做 section 检索 |
|   3 | Stable Identity           | system           | scenario                          | `conversation.customScenario ?? characterCard.scenario`                        | 固定段 | 两者都为空则跳过                                                       |
|   4 | Stable Identity           | system           | slowPlot directive                | `conversation.slowPlotMode == true`                                            | 条件段 | beta；默认开启                                                      |
|   5 | Stable Conversation State | system           | compressed context                | `ContextManager` compression checkpoint summary                                | 动态段 | 无 checkpoint summary 时跳过                                       |
|   6 | Stable Conversation State | user / assistant | checkpoint 后会话历史                  | `ContextManager` 返回的 checkpoint 后 `processedHistory`                           | 动态段 | 不包含本轮当前输入                                                      |
|   7 | Current-Turn Context      | system           | example dialogs block             | `characterCard.exampleDialogs`                                                 | 可选段 | 以带标签的 system block 注入，不再作为原始 user/assistant 示例消息注入             |
|   8 | Current-Turn Context      | system           | world book entries block          | `BackgroundPacket.entries` 中 `.worldBook` selected entries；旧 overload 可消费 preselected world book entries | 动态段 | Phase 6 保持 `[World Book Entries]` 兼容格式；semantic-only 条目不再二次 keyword 过滤 |
|   9 | Current-Turn Context      | system           | memories block                    | `BackgroundPacket.entries` 中 `.memory` selected entries；旧 overload 可消费 direct memories | 动态段 | 按 packet rank / 检索结果顺序和 token 预算裁剪；不按 `importance` 重排 |
|  10 | Current Turn              | user             | current user input + time context | `currentInput` + `PromptAssembler.makeTimeContext()`                           | 固定段 | 同一条 user message 内先放用户输入，再放 `[Time] <ISO8601> [/Time]`         |

旧的 `WorldBookEntryPosition.after_system` / `.before_history` 字段保留为既有数据兼容字段，不再决定最终 prompt 位置。所有当前轮命中的世界书内容最终统一落入 Current-Turn Context 的 world book block。

2026-05-17 Background Phase 6 已把 Chat 主链路的 world book / memory prompt 来源切到 `BackgroundPacket`。Prompt 输出形态没有改变：packet-selected `.worldBook` 条目进入 `[World Book Entries]` block，packet-selected `.memory` 条目进入 `[Memories]` block。统一 `[Background]` block 仍是后续可选迁移。

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

### Role Skill block 规则

当当前角色卡存在 `character_skill_bundle` 绑定时，`ChatViewModel+Support` 通过 `CharacterSkillBundleMaterializer` 读取完整 `content/SKILL.md`，并把它作为 `RoleSkillPromptMaterial` 传入 `PromptAssembler`。`PromptAssembler` 不访问数据库或文件，只把该材料拼成一条 Stable Identity system message：

```xml
[Role Skill]
<role_skill>
<name>{{skillName}}</name>
<source>character_skill_bundle:{{bundleId}}:{{skillMarkdownSha256}}</source>
...完整 SKILL.md...
</role_skill>
[/Role Skill]
```

该实现采用 opencode-style full skill materialization：完整 `SKILL.md` 固定作为 Stable Identity 注入，不做 Codex-style section loader 或 loader traces。Skill ZIP 导入会创建绑定 `character_skill_bundle` 的 OpenChat v2 角色卡；`CharacterSkillBundleEditorView` 可手工编辑该 bundle 的 `SKILL.md` 与已有 `references/**/*.md`，保存后刷新 `skillMarkdownSha256` 和 manifest。若 bundle 内存在 `content/references/**/*.md`，Chat runtime 会通过 Background 的 `.skillReference` source 做本地只读检索，选中片段作为 current-turn background 注入；这不是模型可自由调用的公网 tool-call loop。

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

    /// Chat 主链路在 WorldBookSource 已完成 keyword/semantic 融合后使用。
    /// 此路径不会再次执行 KeywordMatcher，避免 semantic-only entries 被二次过滤。
    static func previewWithPreselectedWorldBookEntries(...)
        -> PromptAssemblyPreview

    static func assembleWithPreselectedWorldBookEntries(...)
        -> AssemblyResult

    /// Chat 主链路当前使用。BackgroundPacket 已由 BackgroundManager / BackgroundWorker 选择，
    /// PromptAssembler 只做兼容 block 生成与 token budget trim。
    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview

    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
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
    let roleSkill: Int
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
function preview(conversation, characterCard, backgroundPacket, history, input, endpoint):
    totalBudget = endpoint.maxContextTokens * 0.40

    // 1. Stable Identity
    sysPrompt = characterCard?.systemPrompt ?? defaultTemplate(characterCard?.name)
    systemMessage = ChatMessage(role: "system", content: sysPrompt)

    if let card = characterCard:
        desc = buildCharacterDescription(card)
        if !desc.isEmpty:
            characterMessage = ChatMessage(role: "system", content: desc)

    if let roleSkill:
        roleSkillMessage = ChatMessage(role: "system", content: makeRoleSkillMessageContent(roleSkill))

    scenario = conversation.customScenario ?? characterCard?.scenario
    if let s = scenario, !s.isEmpty:
        scenarioMessage = ChatMessage(role: "system", content: s)

    if conversation.slowPlotMode:
        slowPlotMessage = ChatMessage(role: "system", content: AppConstants.slowPlotModePrompt)

    stableIdentityMessages =
        [systemMessage]
        + optional(characterMessage)
        + optional(roleSkillMessage)
        + optional(scenarioMessage)
        + optional(slowPlotMessage)

    // 2. Current-Turn Context 候选
    // Chat 主链路传入 BackgroundPacket；旧 preview/assemble 调用方仍通过
    // memories / worldBook entries direct overload 和 KeywordMatcher fallback。
    selectedWorldBookItems = BackgroundAssembler.worldBookItems(from: backgroundPacket)
    selectedMemoryItems = BackgroundAssembler.memoryItems(from: backgroundPacket)

    exampleDialogBlock = makeExampleDialogsBlock(characterCard.exampleDialogMessages())
    worldBookBlock = makeWorldBookBlock(selectedWorldBookItems)
    memoryBlock = makeMemoryBlock(selectedMemoryItems) // preserve packet order

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
3. 若当前角色卡存在 `character_skill_bundle`，`CharacterSkillBundleMaterializer` 从 bundle 目录读取完整 `SKILL.md` 并生成 `RoleSkillPromptMaterial`；没有绑定时返回 `nil`。
4. `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 对当前 world book 做 bounded lazy rebuild；失败记录 warning，不阻断当前回复。该 side effect 仍归 ChatViewModel，不归 BackgroundWorker 或 source adapter。
5. `BackgroundManager.prepare(...)` 调用 Memory / WorldBook source adapters，失败时记录 diagnostics warning；worldBook source failure 会用旧 keyword fallback 生成 `.worldBook` candidates。
6. `BackgroundWorker` 对 `BackgroundCandidate` 做 deterministic selection，输出 `BackgroundPacket`；不联网、不写 DB、不调用 LLM、不生成 assistant message。
7. `PromptAssembler.preview(... backgroundPacket:)` 使用 role skill material、packet-selected worldBook / memory entries 计算 Current-Turn Context、Current Turn、`fixedTokens` 和初始 token usage。
8. `ContextManager.prepareHistory(messages:conversation:endpoint:fixedTokens:)` 只处理过滤后的历史；truncation 返回尾部历史，compression 返回 `[Previously]` checkpoint summary + checkpoint 后历史。
9. `PromptAssembler.assemble(... backgroundPacket: ... processedHistory: ...)` 再次使用同一 role skill material 和 `BackgroundPacket`，拼接 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`，并更新最终 `TokenUsageReport`。

## 7. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/Database` | 读取 CharacterCardRecord、WorldBookEntryRecord、MemoryEntryRecord、ConversationRecord |
| `Core/ContextManager` | PromptAssembler.preview 先计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens；ContextManager 据此处理历史消息（剔除/压缩）；PromptAssembler.assemble 接收 processedHistory |
| `Core/Background` | BackgroundManager / BackgroundWorker 输出 `BackgroundPacket`；BackgroundAssembler 生成兼容 state / skillReference / worldBook / memory prompt items |
| `Core/Memory` | MemoryRecallTool / MemoryBackgroundSource 产出 `.memory` candidates；旧 direct overload 仍可消费 direct memories |
| `Core/WorldBook` | WorldBookRecallTool / WorldBookBackgroundSource 产出 `.worldBook` candidates；worldBook source failure 时 manager 保留 keyword fallback |
| `Core/SkillBundles` | SkillReferenceSearchTool / SkillReferenceBackgroundSource 产出 `.skillReference` candidates；Role skill materializer 读取完整 SKILL.md |
| `Features/Chat` | ChatViewModel 在发送消息时调用 `BackgroundManager.prepare(...)`，再调用 packet-aware `PromptAssembler.preview(...)` / `assemble(...)` |
| `Shared/Extensions` | `String.approximatedTokenCount` 委托 `TokenCounter.count(_:)`，供其他层复用同一估算 |

## 8. 设计决策

1. **40% 上下文预算**：参考用户需求，控制在 40% 以内以保持小模型对当前对话的专注度
2. **四层顺序稳定**：先放 Stable Identity，再放 Stable Conversation State，再放 Current-Turn Context，最后放 Current Turn，避免当前轮检索信息打断角色身份或历史连续性
3. **动态背景注入**：不全量注入世界书或记忆；Chat 主链路注入 `BackgroundPacket` selected entries，manager 保留 worldBook keyword fallback，节省 token
4. **示例对话降级为 labeled system block**：示例对话只表达风格参考，不再伪装成真实 user/assistant 历史，避免污染会话状态
5. **近似 token 计数**：避免引入重型依赖（tiktoken），用近似算法覆盖 90%+ 场景。CJK 文本的误差通过预留余量吸收
6. **预算分配弹性**：历史消息获得最大弹性空间，因为对话质量主要取决于近期上下文
7. **可选段可裁剪**：当 token 紧张时，示例对话优先被裁剪，因为其作用是引导风格而非提供关键信息
8. **慢速剧情推进模式（beta）**：作为条件固定段注入，默认开启，会话级可关闭。提示词内容固定存储于 AppConstants，不可用户编辑。isRequired=false 但 priority=.max（开启时不被裁剪）

## 当前实现证据（更新于 2026-06-02）

- 代码位置：
  - `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift` — `PromptAssemblyPreview` 输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
  - `OpenChat/Core/PromptEngine/PromptAssembler.swift` — `preview(... backgroundPacket:roleSkill:)` / `assemble(... backgroundPacket:roleSkill:)` 是当前 Chat 主链路入口；旧 `preview(...)` / `assemble(...)` 和 `previewWithPreselectedWorldBookEntries(...)` / `assembleWithPreselectedWorldBookEntries(...)` 保留作兼容 / rollback；最终输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
  - `OpenChat/Core/SkillBundles/SkillBundleMaterializer.swift` — 从 `character_skill_bundle` metadata 和 bundle storage 读取完整 `SKILL.md`，生成 `RoleSkillPromptMaterial`。
  - `OpenChat/Core/SkillBundles/CharacterSkillBundleStore.swift` — 解析 Application Support 下的 bundle/content 路径，读取 / 写回 SKILL.md，枚举 / 读取 / 写回 `content/references/**/*.md`，并生成 content manifest。
  - `OpenChat/Core/SkillBundles/SkillReferenceSearchTool.swift` — 本地只读 `skill_reference_search` 第一版：按当前输入检索当前角色绑定 bundle 的 references markdown，输出 `.skillReference` candidates。
  - `OpenChat/Core/Background/BackgroundAssembler.swift` — 将 packet entries 转为兼容 state / skillReference / worldBook / memory prompt items，diagnostics / score / omission 不进入 prompt content。
  - `OpenChat/Core/Background/BackgroundManager.swift` — 组合 source adapters 与 worker；worldBook source failure 保留 keyword fallback candidates。
  - `OpenChat/Core/WorldBook/WorldBookSource.swift` — keyword candidates + semantic KNN 融合，semantic unavailable fallback 到 keyword-only。
  - `OpenChat/Core/WorldBook/WorldBookRecallModels.swift` — recall trace / reason / omission DTO。
  - `OpenChat/Core/PromptEngine/PromptSegment.swift` — 使用 `.exampleDialogsBlock(String)` 与 `.currentTurn(String)` 表达目标语义；time context 不再是独立 segment。
  - `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` — `generateResponse(...)` 串联 `role skill materialization -> bounded worldBook rebuild -> BackgroundManager.prepare -> PromptAssembler.preview(backgroundPacket:roleSkill:) -> prepareHistory -> PromptAssembler.assemble(backgroundPacket:roleSkill:)`，并通过 `makePromptHistoryMessages(...)` 过滤本轮 user record，避免当前输入在历史和末尾 user 消息中重复。
  - `OpenChat/Features/CharacterCard/ViewModels/CharacterSkillBundleEditorViewModel.swift` — OpenChat v2 角色卡手工编辑保存链路，更新 `SKILL.md`、references、bundle metadata 与角色卡摘要。
  - `OpenChat/Core/PromptEngine/KeywordMatcher.swift`
  - `OpenChat/Core/PromptEngine/TokenCounter.swift`
  - `OpenChat/Core/PromptEngine/TokenBudget.swift`
  - `OpenChat/App/AppConstants.swift` — slowPlotModePrompt 常量
  - `OpenChat/Core/Database/Records/ConversationRecord.swift` — slowPlotMode 字段
  - `OpenChat/Core/Database/Migrations.swift` — v7_add_slow_plot_mode 迁移
  - `OpenChat/Core/ContextManager/PreparedHistory.swift` — compression checkpoint 通过 `[Previously]` system message 进入 Stable Conversation State。
- 已验证测试：
  - `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`（含慢速模式开/关/token 预算测试；覆盖四层顺序、role skill block 注入、preview 四层输出、labeled example/world book/memory blocks、packet compatible block、packet budget trim、世界书 position 兼容、semantic candidate block 兼容、current turn 内时间上下文）
  - `OpenChatTests/Core/SkillBundleTests/CharacterSkillBundleMaterializerTests.swift`（覆盖已有 `character_skill_bundle` 绑定读取完整 SKILL.md，以及无绑定返回 nil）
  - `OpenChatTests/Core/SkillBundleTests/SkillReferenceSearchToolTests.swift`（覆盖绑定 bundle references 检索、无绑定空结果和 `.skillReference` candidate metadata 映射）
  - `OpenChatTests/Features/CharacterCardTests/CharacterSkillBundleEditorViewModelTests.swift`（覆盖 OpenChat v2 角色卡编辑保存后 materializer 读取新 `SKILL.md`，并刷新 metadata / manifest）
  - `OpenChatTests/Core/WorldBookTests/WorldBookSourceTests.swift`（覆盖 keyword-only、semantic-only、keyword+semantic duplicate merge、disabled world/entry、semantic failure fallback）
  - `OpenChatTests/Core/PromptEngineTests/KeywordMatcherTests.swift`
  - `OpenChatTests/Core/PromptEngineTests/TokenCounterTests.swift`
  - `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`（覆盖真实发送链路中当前输入只发送一次、API request 四层顺序、已有角色 skill bundle 的完整 SKILL.md 注入、request body 使用 `BackgroundPacket` selected entries、semantic world book entry 进入 `[World Book Entries]` block、worldBook semantic failure keyword fallback、memory fallback 注入、checkpoint invalidation、compression mode 持久化）
  - `OpenChatTests/Core/ContextManagerTests/CompressionCheckpointReuseTests.swift`
- 当前实现描述：
  - Chat 主链路的背景候选由 `BackgroundManager` 协调 SkillReference / Memory / WorldBook source adapters；`recentMessages` 应排除本轮当前输入。
  - `PromptAssembler` 不访问数据库、不调用 embedding/KNN、不读取 bundle 文件；它只消费调用方传入的 `RoleSkillPromptMaterial`、`BackgroundPacket` 或旧 direct 条目，生成 block 并按预算裁剪。
  - Role skill 采用完整 `SKILL.md` 注入；references 通过 `.skillReference` background source 做本地片段检索；Skill ZIP 导入和 OpenChat v2 Skill 编辑器均维护同一份 bundle content 与 metadata。
  - 示例对话以 `[Example Dialogs]` labeled system block 注入，位于 Stable Conversation State 之后。
  - 世界书条目统一进入 `[World Book Entries]` block，不再按 `after_system` / `before_history` 拆分最终位置。
  - 记忆条目统一进入 `[Memories]` block，位于 world book block 之后。
  - 时间上下文位于最后一条 current turn user message 内，用户输入在前，`[Time] <ISO8601> [/Time]` 在后。
  - `assemble(...)` / `assembleWithPreselectedWorldBookEntries(...)` 只接收 ContextManager 已处理的 `processedHistory`，不会自行截断或压缩历史。
- 验证记录：
  - `harness/2026.04.30/checkpoint-compression/evidence.txt`
  - `arch/AntiEntropy/triangle-consistency.md#checkpoint-compression-三边一致性写回2026-04-30`
  - 2026-05-16 Phase C focused suite：`WorldBookSourceTests` + `PromptAssemblerTests` + `ChatViewModelPromptAssemblyTests`，34 tests / 3 suites passed，`** TEST SUCCEEDED **`。
