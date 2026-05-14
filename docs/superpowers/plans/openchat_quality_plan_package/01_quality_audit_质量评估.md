# 01. 多维度质量评估

## 1. 架构与模块边界

### 优点

项目有明确的四层结构：`App / Features / Core / Shared / Resources`。`AGENTS.md` 明确写出单向依赖规则：`App → Features → Core → Shared`，并要求 Feature 间隔离、MVVM、依赖注入、迁移只追加。这说明项目不是边写边堆，而是有架构约束和文档治理意识。

`DependencyContainer` 统一装配 `DatabaseManager`、`APIClient`、`ContextManager`、`MemoryManager`、`TitleGenerator`，主链路依赖注入思路正确。Core 层按 Database、Networking、PromptEngine、ContextManager、Memory 分模块，职责划分基本合理。

### 问题

当前源码已经出现分层漂移：Core 直接使用 `AppConstants`，Feature ViewModel 持有 `AppState`，`Features/Support/SidebarView.swift` 承担 App shell 跨 Feature 组装，`WorldBookEditorView` 直接打开 CharacterCard UI，`Shared/Extensions/String+Token.swift` 调用 Core 的 `TokenCounter`。这些问题已经在 `arch/AntiEntropy/layering-repair-plan.md` 中被项目自己记录，说明团队已经识别到风险，但还没有关闭。

### 评价

架构方向正确，文档约束强，但需要把“约束”变成自动化测试。否则 Codex/协作式开发很容易继续扩大跨层引用。

## 2. 数据库与持久化

### 优点

GRDB 使用较规范，Record 类型覆盖核心表，迁移从 v1 到 v12 采取 append-only 风格。表结构覆盖 endpoint、模型、角色卡、世界书、对话、消息、记忆、压缩 checkpoint 等。`DatabaseManager` 封装读写入口，`Configuration` 中启用 foreign key，并注册 sqlite-vec。

### 问题

1. API Key 明文存在 `api_endpoint.apiKey`。
2. `memory_embedding` 是 sqlite-vec 虚拟表，没有外键级联，`eraseAllData` 删除角色卡/记忆时不显式删除向量，可能留下孤儿向量。
3. 默认 endpoint/default model 依赖运行时更新，没有数据库唯一索引兜底。
4. message `sortOrder` 通过 `max + 1` 计算，缺少 `(conversationId, sortOrder)` 唯一约束，存在并发/多窗口重复序号风险。
5. 多个字段用 JSON TEXT 存数组或参数，解码失败常用 `try?` 隐式吞掉，容易让坏数据静默变成空值。
6. 记忆提取游标用“最近 memory createdAt”推导，若一次提取没有产出记忆，后续可能重复处理同一批消息。

### 评价

数据库能力已经超出普通 demo，但一致性约束还不够“数据库化”。下一步应让 DB schema 承担关键不变量，而不是只靠 ViewModel/Manager 逻辑维持。

## 3. 网络层与 API 兼容

### 优点

`APIClient` 对 Chat Completions 与 Responses API 做了模式分发，支持同步和流式。SSE 解析抽成 `SSEStreamParser`，测试覆盖较多。流式响应中支持 content、reasoning、usage 等信息，说明已考虑 DeepSeek/Responses 这类扩展能力。

### 问题

1. 使用 `.shared` URLSession，未设置 endpoint 级超时、重试、退避策略。
2. 流式 HTTP 错误验证时通常拿不到响应 body，用户看到的信息可能不足。
3. HTTP 错误 body 直接拼进 `errorDescription`，可能过长或泄漏敏感信息。
4. Responses API 事件处理较窄，未知事件直接忽略，失败/不完整状态缺少更细的恢复/提示。
5. `/models` 获取假设偏 OpenAI-compatible，对 Ollama、本地服务、非标准兼容服务的兼容层还不足。

### 评价

网络层基础扎实，但还处于“能跑主路径”的阶段。要支撑真实用户，需要 timeout/retry/cancel/error hygiene。

## 4. Chat 生成链路与并发

### 优点

`ChatViewModel` 主链路完整：保存用户消息、读取角色卡/世界书/历史、检索记忆、组装 prompt、调用 ContextManager、发起流式请求、追加 assistant delta、记录 token usage、触发记忆提取。这个链路设计符合 AI RP 客户端的核心需求。

### 问题

1. `ChatViewModel` 是 `@MainActor`，其 extension 中 `Task { [weak self] ... }` 继承 MainActor 语境。网络 await 本身不会直接阻塞 UI，但流式循环内的 JSON/状态处理都在 UI actor 上，长流或高频 delta 时可能造成 UI 抖动。
2. `stopGenerating()` 只 cancel task，取消后的部分内容没有一致的落库策略。
3. 失败 catch 中只移除“空占位 assistant”，如果已经有部分内容，则会保留在 UI 但不落库，刷新后消失，用户体验不一致。
4. `isGenerating` 和 `streamTask` 清理没有用 `defer`，未来改动时容易漏清理。
5. 未见 View 消失/deinit 时取消 streamTask 的明确策略。

### 评价

主流程可用，但“长时间流式生成 + 用户中断 + 网络失败 + 切页”这些真实场景需要补强。

## 5. Prompt、上下文与 RP 业务逻辑

### 优点

Prompt 四层顺序已经落地：Stable Identity、Stable Conversation State、Current-Turn Context、Current Turn。当前输入与历史去重、世界书触发、记忆注入、时间上下文、slowPlot directive、checkpoint 压缩都已经具备。对小模型上下文限制做 40% 预算控制，符合本地模型/RP 长对话使用场景。

### 问题

1. TokenCounter 是启发式估算，不同 provider/model 误差可能较大。
2. 预算策略固定使用 maxContextTokens 的 40%，缺少 per-model 调参和安全余量。
3. trim 函数允许第一个 oversized block 被完整纳入，可能突破预算。
4. 角色卡、世界书、记忆等用户可编辑内容没有明显 prompt-injection 边界声明。
5. Prompt 字符串大多硬编码英文；面向中文/日文 RP 时可能影响风格一致性。
6. 世界书触发还比较基础，缺少 regex、negative keywords、constant entries、递归触发、深度、概率等 lorebook 常见能力。

### 评价

AI/RP 的方向和底座很好。后续重点是稳定、可控、可解释，而不是盲目增加 prompt 长度。

## 6. 记忆系统与向量检索

### 优点

Memory 有协议化依赖、embedding/vector 分离、异常 fallback 到近期记忆。`VectorStore.insert(entries:)` 采用事务保存 memory entry + embedding，基本符合一致性需求。记忆以角色卡为单位跨会话共享，业务设定合理。

### 问题

1. 嵌入模型权重被移除是正常的，但测试和运行时要对“资源缺失”有明确 fallback/skip。
2. 记忆提取游标不可靠，建议改为 `lastProcessedMessageSortOrder` 或独立 state table。
3. Memory extraction prompt 用英文硬编码，且 JSON 解析容错需继续强化。
4. 向量表清理与 `eraseAllData` 不闭环。
5. 记忆质量缺少反馈机制：用户无法标记某条记忆错误、过期、隐私敏感或不应注入。

### 评价

这是项目亮点之一，但要防止“错误记忆长期污染角色”。记忆系统需要数据治理能力。

## 7. UI、UX 与产品完成度

### 优点

SwiftUI 表单和列表基础完整，设置、聊天、角色卡、世界书都有对应视图和 ViewModel。Localizable 字符串资源已经存在，说明有国际化意识。

### 问题

1. Settings 的全量导入导出未接线，直接抛错误。
2. 多个保存按钮使用 `try?` 后直接 dismiss，保存失败用户可能毫无感知。
3. API Key 输入使用普通 `TextField`，不应明文显示。
4. 角色卡示例对话编辑、头像选择、完整导入导出等功能仍不完整。
5. 世界书 Markdown 导入解析规则过于脆弱，只适合非常固定的格式。

### 评价

核心功能可操作，但产品化细节明显不足。优先修复“用户数据不要丢、错误要看见”。

## 8. 测试与工程流程

### 优点

测试数量不少，覆盖 Core 的数据库迁移、网络、Responses、thinking、Prompt、Context、Memory 等。对一个 Codex 协作项目来说，这是明显优点。

### 问题

1. 未见 GitHub Actions/CI workflow。
2. 未见 SwiftLint/SwiftFormat 配置。
3. UI 与 Feature ViewModel 的测试不足。
4. 架构边界依赖文档约束，没有自动化源码扫描测试。
5. 资源依赖测试在模型权重缺失时可能失败，需要 mock/skip。

### 评价

测试基础已经“值得保留”，但工程质量需要从“写了不少测试”升级到“任何协作者提交都能自动验证”。
