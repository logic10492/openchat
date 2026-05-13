# 跨对话记忆模块设计

> 所属层：`Core/Memory/` + `Features/CharacterCard/`
> 依赖：Core/Database（MemoryEntryRecord）, Core/Networking（APIClient）, Shared/Extensions

## 1. 功能范围

- 同一角色跨对话的记忆存储与语义检索
- 本地嵌入模型推理（CoreML MultilingualE5Small）
- 向量存储与 KNN 相似度检索（sqlite-vec）
- Chat 生成链路中按周期自动提取关键事件/摘要作为记忆条目
- 新对话开始时拉取角色近期记忆摘要
- 每次发送消息时检索与当前输入语义相关的记忆
- 记忆条目的查看、搜索与删除管理

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `Core/Memory/EmbeddingService.swift` | CoreML MultilingualE5Small 模型加载、XLMRobertaTokenizer 分词与向量推理 |
| `Core/Memory/XLMRobertaTokenizer.swift` | 读取 `tokenizer.json` 的 Unigram vocab，输出固定长度 input IDs / attention mask |
| `Core/Memory/MemoryDependencies.swift` | `EmbeddingProvider`、`MemoryVectorStore` 协议边界，支持测试注入与批次原子写入 |
| `Core/Memory/VectorStore.swift` | sqlite-vec 向量 CRUD 封装（原子插入 / KNN 检索 / 删除） |
| `Core/Memory/MemoryManager.swift` | 记忆提取与检索的编排层 |
| `Core/Memory/MemoryError.swift` | 记忆模块统一错误类型 |
| `Core/Database/Records/MemoryEntryRecord.swift` | GRDB Record：记忆条目 |
| `Features/CharacterCard/Views/MemoryListView.swift` | 角色卡详情入口下的记忆列表界面 |
| `Features/CharacterCard/ViewModels/MemoryListViewModel.swift` | 记忆列表状态管理 |

## 3. 数据结构

### 3.1 memory_entry 表

详见 `data-model.md`。核心字段：

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| characterCardId | TEXT | NOT NULL, FK → character_card.id | 所属角色卡 |
| sourceConversationId | TEXT | FK → conversation.id | 来源对话（可选） |
| content | TEXT | NOT NULL | 记忆原文（摘要 / 事件描述） |
| memoryType | TEXT | NOT NULL | `event` / `fact` / `relationship` / `summary` |
| importance | INTEGER | NOT NULL, DEFAULT 50 | 重要性评分（0-100） |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**外键**：
- `characterCardId` → `character_card(id)` ON DELETE CASCADE
- `sourceConversationId` → `conversation(id)` ON DELETE SET NULL

### 3.2 memory_embedding 虚拟表

sqlite-vec 虚拟表，存储记忆条目的向量嵌入：

```sql
CREATE VIRTUAL TABLE memory_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

与 `memory_entry.id` 通过 `entry_id` 关联。

### 3.3 记忆类型枚举

```swift
enum MemoryType: String, Codable, Sendable {
    case event         // 具体事件（如 "玩家在森林中救了一只受伤的精灵"）
    case fact          // 事实信息（如 "玩家的名字是凯文"）
    case relationship  // 关系变化（如 "角色对玩家产生了好感"）
    case summary       // 对话整体摘要
}
```

## 4. 嵌入模型

### 4.1 模型选型

| 项目 | 详情 |
|---|---|
| 模型 | MultilingualE5Small |
| 格式 | CoreML (.mlpackage → .mlmodelc) |
| 输出维度 | 384 |
| 分词器 | XLMRobertaTokenizer（`OpenChat/Resources/Models/tokenizer.json`） |
| CoreML 输入长度 | 256 tokens（`input_ids` / `attention_mask` shape 为 `1 x 256`） |
| 多语言支持 | 是（中 / 英 / 日 等 100+ 语言） |
| 模型文件 | `OpenChat/Resources/Models/MultilingualE5Small.mlpackage`（源码保留 `models/MultilingualE5Small.mlpackage.zip`） |

### 4.2 E5 前缀规范

E5 模型要求输入文本添加任务前缀以区分查询与文档：

| 场景 | 前缀 | 示例 |
|---|---|---|
| 存储记忆（passage） | `"passage: "` | `"passage: 玩家在森林中救了一只受伤的精灵"` |
| 检索查询（query） | `"query: "` | `"query: 精灵森林发生了什么"` |

### 4.3 EmbeddingService 接口

```swift
final class EmbeddingService: @unchecked Sendable {
    /// 将文本转换为 384 维归一化向量
    /// - text: 原始文本（不含前缀）
    /// - isQuery: true 添加 "query: " 前缀，false 添加 "passage: " 前缀
    /// - returns: 归一化的 [Float] 向量，维度 384
    func embed(_ text: String, isQuery: Bool) throws -> [Float]
}
```

**加载策略**：
- **实例内 lazy 加载**：`DependencyContainer` 创建 `EmbeddingService` 实例，首次调用 `embed()` 时才加载 CoreML 模型，避免阻塞 App 启动
- **线程安全**：`NSLock` 保护 lazy `MLModel` 与 tokenizer；模拟器使用 CPU，真机使用 CPU/GPU
- **分词**：使用 App Bundle 内的 `tokenizer.json`（XLMRobertaTokenizer），超过 256 tokens 的输入自动截断
- **输出读取**：当前 CoreML 输出 feature 为 `embeddings`，支持 Float16 / Float32，结果必须为 384 维并归一化

## 5. 向量存储

### 5.1 集成方式

通过 **SPM 包**引入 sqlite-vec，在 `DatabaseManager` 初始化时加载扩展。

### 5.2 VectorStore 接口

```swift
struct VectorStore: Sendable {
    /// 插入向量嵌入
    func insert(entryId: String, embedding: [Float]) async throws

    /// 同一事务中插入 memory_entry 和 memory_embedding
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws

    /// 同一事务中批量插入 memory_entry 和 memory_embedding；任一条失败时整批回滚
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws

    /// KNN 相似度检索
    /// - query: 查询向量
    /// - characterCardId: 限定角色卡范围
    /// - limit: 返回条目数上限
    /// - returns: 按相似度降序排列的 (entryId, distance) 数组
    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)]

    /// 删除向量嵌入
    func delete(entryId: String) async throws

    /// 批量删除（用于清空角色全部记忆）
    func deleteAll(characterCardId: String) async throws
}
```

**检索实现**：sqlite-vec 的 KNN 查询使用 `embedding MATCH ? AND k = ?`，并在 KNN 前通过 `entry_id IN (SELECT id FROM memory_entry WHERE characterCardId = ?)` 限定角色卡范围。

**一致性约束**：
- `MemoryVectorStore.insert(entries:)` 是协议必填方法，不提供顺序单条写入的默认实现。
- 生产 `VectorStore.insert(entry:embedding:)` 与 `VectorStore.insert(entries:)` 在同一个 GRDB write transaction 内同时写入 `memory_entry` 与 `memory_embedding`。
- 所有向量写入前校验维度必须为 `EmbeddingService.embeddingDimension == 384`；批量写入先完成所有维度校验和 blob 转换，再进入事务。

## 6. 记忆提取流程

### 6.1 触发时机

当前实现采用**发送链路内的前置同步提取**，提取发生在**用户消息持久化之后、检索记忆之前**：

- `ChatViewModel` 每完成一轮 user + assistant 生成后将 `messagesSinceLastExtraction += 2`。
- 当计数达到 `ChatViewModel.extractionInterval == 10` 时，在下一次 `generateResponse` 中同步等待 `MemoryManager.extractMemories(from:)` 完成，再执行记忆检索。
- 提取期间 UI 通过 `extractionPhase` 状态显示内联指示器（详见 6.5）。
- `ChatView.onDisappear` 也会调用 `triggerMemoryExtraction()`（fire-and-forget），因此离开当前聊天视图或切换对话时可能触发提取。

与旧方案（响应完成后异步提取）相比：
- 提取时间点确定性更高，不会因 ViewModel 重建或页面退出丢失
- 新提取的记忆**立即可用**于当前轮次的语义检索
- cutoff 使用 `conversation.lastExtractedSortOrder` 而非 `memory_entry.createdAt`，避免消息被永久跳过

App 进入后台的 lifecycle hook 不属于当前源码行为，作为后续 UX/生命周期增强项单独规划。

### 6.2 提取步骤

```
extractMemories(from conversation):
    1. 从 DB 重新读取最新 ConversationRecord，确认已绑定 characterCardId
    2. 读取 conversation.lastExtractedSortOrder 作为增量 cutoff（首次提取时为 nil）
    3. 从 DB 加载该对话消息，仅保留 sortOrder > cutoff 的新消息；cutoff 为 nil 时使用全部消息
    4. 如果新消息数 < minimumMessagesForExtraction（当前 4 条），跳过提取
    5. 构建提取 prompt（见 6.3）
    6. 调用 APIClient.sendMessage()（非流式，使用对话关联的端点）
    7. 解析 API 返回的 JSON 数组
    8. 对每条提取出的记忆先创建 MemoryEntryRecord，并调用 EmbeddingProvider.embed(content, isQuery: false) 生成向量
    9. 调用 MemoryVectorStore.insert(entries:) 批量原子保存 memory_entry + memory_embedding
       - 任一 embedding 或 vector 写入失败，本批次整体失败
       - 不留下只有 memory_entry、没有 memory_embedding 的半索引记忆
    10. 提取成功后更新 conversation.lastExtractedSortOrder = messages.last?.sortOrder
```

### 6.3 提取 Prompt 模板

```
System: You are a memory extraction assistant. Analyze the following conversation
and extract key memories. Return a JSON array with the following structure:

[
  {
    "content": "Brief description of the memory",
    "type": "event|fact|relationship|summary",
    "importance": 0-100
  }
]

Rules:
- Extract important events, facts about the user, relationship changes, and conversation summaries
- importance: 90-100 for critical plot points, 50-70 for general events, 30-50 for minor details
- Keep each memory concise (1-2 sentences)
- Return ONLY the JSON array, no other text

Conversation:
{messages formatted as "role: content"}
```

### 6.4 增量 cutoff 策略

- 通过 `conversation.lastExtractedSortOrder` 记录上次提取处理到的消息 sortOrder 边界。
- 若存在上次 cutoff，只处理 `sortOrder > lastExtractedSortOrder` 的新消息；若不存在（首次提取），则处理该对话全部消息。
- 新消息数少于 `MemoryManager.minimumMessagesForExtraction` 时跳过本轮提取。
- 提取成功后立即更新 `conversation.lastExtractedSortOrder` 为本批消息的最大 sortOrder。
- 使用 sortOrder 而非 `createdAt` 的原因：并发提取期间新写入的消息 sortOrder 更大，不会被跳过；而 `createdAt` 可能因时间精度或提取延迟导致边界模糊。
- 后续可扩展：对新提取的记忆与已有记忆做向量相似度比较，去除高度重复条目

### 6.5 提取 UI 指示器

提取期间通过 `ChatViewModel.extractionPhase` 驱动内联 UI 指示器，显示在用户消息与助手响应之间：

```swift
enum MemoryExtractionPhase: Sendable, Equatable {
    case idle                                       // 无提取
    case extracting                                 // API 调用中
    case completed(count: Int, summaries: [String])  // 提取完成
    case skipped                                    // 消息不足，不触发
    case failed(description: String)                // 提取失败
}
```

| 状态 | 图标 | 文本 | 样式 |
|---|---|---|---|
| `extracting` | 🧠 脉冲动画 | "正在提取记忆…" | `.caption.italic()`, `.secondary`, 居中 |
| `completed(N, _)` | 🧠 | "提取了 N 条记忆" | `.caption.italic()`, `.secondary`, 居中, 可展开 |
| `failed` | ⚠️ | "记忆提取失败" | `.caption.italic()`, `.red.opacity(0.7)`, 居中 |
| `idle` / `skipped` | — | — | 不渲染 |

**交互**：`completed` 状态下轻点可展开/收起具体记忆列表。提取完成后 3 秒自动过渡为 `idle`。

**实现**：`MemoryExtractionIndicator` view 替代旧的 `MemoryMarkerView` + `MessageDisplayItem.memoryMarker()`。

## 7. 记忆检索流程

### 7.1 新对话开始时

```
retrieveRecentSummary(for characterCardId, limit: 5):
    1. 从 DB 按 createdAt 倒序查询该角色最近 N 条记忆
    2. 优先返回 type == .summary 的条目
    3. 结果传入 PromptAssembler 作为初始记忆上下文
```

### 7.2 每次发送消息时

```
retrieveMemories(for characterCardId, query: currentInput, limit: 5):
    1. 调用 EmbeddingService.embed(query, isQuery: true) 生成查询向量
    2. 调用 VectorStore.search(query, characterCardId, limit) 执行 KNN 检索
    3. 若 embedding/model/vector 检索异常，记录 warning 并 fallback 到 retrieveRecentSummary()
    4. 过滤掉 distance 超过阈值的结果（相关度过低）
    5. 从 DB 加载对应的 MemoryEntryRecord，并按 KNN 返回的 entry_id 顺序恢复结果
    6. 与 retrieveRecentSummary() 结果合并去重
    7. 结果传入 PromptAssembler
```

### 7.3 注入方式

检索到的记忆作为 Current-Turn Context 的 `[Memories]` labeled system block 注入 prompt：
- **位置**：Stable Conversation State 之后，`[Example Dialogs]` 与 `[World Book Entries]` 之后，最后一条 Current Turn user message 之前
- **role**: `"system"`
- **priority**: 85（高于 exampleDialogsBlock:75，低于世界书条目最大值）
- **token 预算**: 上限为剩余预算 × 15%
- **格式**: 多条记忆合并进一条 `[Memories] ... [/Memories]` system message

## 8. MemoryManager 接口

```swift
struct MemoryManager: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingService: any EmbeddingProvider
    private let vectorStore: any MemoryVectorStore
    private let apiClient: APIClient

    /// 从对话中提取记忆（后台异步调用）
    func extractMemories(from conversation: ConversationRecord) async throws -> [MemoryEntryRecord]

    /// 语义检索相关记忆（每次发送消息时调用）
    func retrieveMemories(
        for characterCardId: String,
        query: String,
        limit: Int = 5
    ) async throws -> [MemoryEntryRecord]

    /// 获取角色近期记忆摘要（新对话开始时调用）
    func retrieveRecentSummary(
        for characterCardId: String,
        limit: Int = 5
    ) async throws -> [MemoryEntryRecord]

    /// 删除单条记忆
    func deleteMemory(id: String) async throws

    /// 清空角色的全部记忆
    func deleteAllMemories(for characterCardId: String) async throws
}
```

通过 `DependencyContainer` 注入，由 `ChatViewModel` 持有引用。

## 9. 错误处理

```swift
enum MemoryError: LocalizedError {
    case modelLoadFailed(underlying: Error)
    case embeddingFailed(underlying: Error)
    case vectorStoreError(underlying: Error)
    case extractionFailed(reason: String)
    case invalidExtractionResponse
}
```

记忆系统的错误处理遵循“聊天主流程优先，但故障可观测”：

- 检索链路：`MemoryManager.retrieveMemories(...)` 捕获 embedding/model/vector 检索异常，记录 warning 并 fallback 到 `retrieveRecentSummary(...)`；只有 fallback 本身也失败时才继续向上抛出，Chat 层记录 warning 后继续生成。
- 提取链路：`MemoryManager.extractMemories(from:)` 对同一批提取结果采用批量原子写入；embedding 或 vector 任一失败时整批失败并记录 error，不推进 `latestMemoryDate`。
- UI 链路：提取失败会通过 Chat memory marker 反馈；检索 fallback 成功时用户发送流程继续，且 prompt 仍包含近期记忆。

## 10. 视图设计

### 10.1 MemoryListView

```
┌─────────────────────────────────────────┐
│ [←] 艾拉的记忆                   [清空] │
│─────────────────────────────────────────│
│ [🔍 搜索记忆...]                        │
│─────────────────────────────────────────│
│ ┌─ 事件 ─────────────────────────────┐  │
│ │ 玩家在森林中救了一只受伤的精灵      │  │
│ │ 重要性: ████████░░ 80  · 2 天前    │  │
│ └────────────────────────────────────┘  │
│ ┌─ 关系 ─────────────────────────────┐  │
│ │ 角色对玩家产生了好感                │  │
│ │ 重要性: █████████░ 90  · 1 天前    │  │
│ └────────────────────────────────────┘  │
│ ┌─ 事实 ─────────────────────────────┐  │
│ │ 玩家的名字是凯文                    │  │
│ │ 重要性: ██████░░░░ 60  · 3 天前    │  │
│ └────────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

- 按时间倒序展示，左侧标注 memoryType 标签
- 左滑删除单条
- 右上角"清空"按钮：确认后删除该角色全部记忆
- 搜索栏：本地文本过滤

### 10.2 MemoryListViewModel

```swift
@Observable
final class MemoryListViewModel {
    private let databaseManager: DatabaseManager
    private let memoryManager: MemoryManager
    let characterCardId: String

    private(set) var memories: [MemoryEntryRecord] = []
    var searchText: String = ""

    var filteredMemories: [MemoryEntryRecord]  // 根据 searchText 过滤

    func loadMemories() async
    func deleteMemory(_ id: String) async throws
    func deleteAllMemories() async throws
}
```

### 10.3 入口

- **角色详情页**（`CharacterCardDetailView`）新增 "记忆" section：
  - 显示该角色的记忆条目总数
  - 点击进入 `MemoryListView`

## 11. 与其他模块的交互

| 交互对象 | 交互方式 |
|---|---|
| `Core/PromptEngine` | 检索到的记忆作为 `PromptSegment.memoryEntry` 注入 prompt，token 预算上限为剩余预算 × 15% |
| `Features/Chat` | `ChatViewModel` 在发送消息时调用 `retrieveMemories()`；每累计 10 条 user/assistant 消息后周期性调用 `extractMemories()`；`ChatView.onDisappear` 也会触发提取 |
| `Core/Database` | `MemoryEntryRecord` CRUD + `memory_embedding` sqlite-vec 虚拟表操作；原子写入由 `VectorStore` 的 GRDB transaction 统一编排 |
| `Core/Networking` | 记忆提取时调用 `APIClient.sendMessage()` 请求 LLM 提取结构化记忆 |
| `Features/CharacterCard` | 角色详情页提供记忆列表入口 |

## 12. 设计决策

1. **摘要/事件级粒度**：不存储原始消息向量（量大且噪声高），而是提取关键事件/摘要后向量化，质量更高
2. **本地嵌入模型**：使用 CoreML 在设备端推理，无需网络请求，保护用户隐私
3. **sqlite-vec**：复用已有的 SQLite 基础设施，无需引入独立的向量数据库
4. **15% memory token 预算**：避免记忆占用过多上下文空间，保持当前对话质量
5. **可观测降级**：记忆系统故障不应影响核心聊天功能；语义检索失败 fallback 到近期记忆并记录日志
6. **前置同步提取 + 视图消失触发**：当前源码每累计 10 条 user/assistant 消息后在下次 generateResponse 中同步提取，提取结果立即可用于当前轮检索；`ChatView.onDisappear` 保留 fire-and-forget 触发；App 进入后台 lifecycle hook 另行规划
7. **sortOrder 边界替代 createdAt cutoff**：通过 `conversation.lastExtractedSortOrder` 记录已处理消息边界，避免并发写入或时间精度导致消息被永久跳过
8. **提取过程可观测**：`extractionPhase` 状态驱动内联 UI 指示器，用户可实时感知提取状态

## 13. 实现证据

> Phase 7 实现完成（对应 roadmap.md）

### 已实现文件

| 设计文件 | 实现位置 | 说明 |
|---|---|---|
| EmbeddingService | `Core/Memory/EmbeddingService.swift` | `final class: @unchecked Sendable`，NSLock 保护 lazy MLModel + XLMRobertaTokenizer，固定 256 输入，输出 384 维归一化向量 |
| XLMRobertaTokenizer | `Core/Memory/XLMRobertaTokenizer.swift` | tokenizer.json Unigram vocab 解析，compatibility normalization，固定长度 input IDs / attention mask |
| MemoryDependencies | `Core/Memory/MemoryDependencies.swift` | `EmbeddingProvider` / `MemoryVectorStore` 协议，显式 batch insert 语义 |
| VectorStore | `Core/Memory/VectorStore.swift` | sqlite-vec 封装，insert/search/delete/deleteAll；memory/vector 原子写入 |
| MemoryManager | `Core/Memory/MemoryManager.swift` | struct Sendable，提取+检索编排 |
| MemoryError | `Core/Memory/MemoryError.swift` | MemoryType enum + MemoryError enum |
| MemoryEntryRecord | `Core/Database/Records/MemoryEntryRecord.swift` | GRDB FetchableRecord + PersistableRecord |
| DatabaseManager+Memory | `Core/Database/DatabaseManager+Memory.swift` | 8 个 CRUD 方法 |
| MemoryListView | `Features/CharacterCard/Views/MemoryListView.swift` | 搜索+删除+清空 UI |
| MemoryListViewModel | `Features/CharacterCard/ViewModels/MemoryListViewModel.swift` | @Observable MVVM |
| sqlite-vec SPM | `Packages/SqliteVec/` | 本地 C 包，v0.1.9 |
| 迁移 v4 | `Core/Database/Migrations.swift` | memory_entry 表 + memory_embedding vec0 虚拟表 |

### 关键集成点

- `DependencyContainer` → 注入 `MemoryManager`（含 `EmbeddingService` + `VectorStore`，经协议边界使用）
- `ChatViewModel` → 持有 `memoryManager`，发送消息时 `retrieveMemories()`；语义检索失败时由 MemoryManager fallback 到近期记忆；每 10 条 user/assistant 消息后周期性 `triggerMemoryExtraction()`；`ChatView.onDisappear` 也会触发提取
- `PromptAssembler` → `memories: [MemoryEntryRecord]` 参数，`makeMemoryMessageContent()` 格式化
- `TokenBudget` → `memoryBudget`（remaining × 15%）
- `PromptSegment` → `.memoryEntry(MemoryEntryRecord)` + `.exampleDialogsBlock(String)` + `.currentTurn(String)`
- `CharacterCardDetailView` → Memory section 显示计数 + NavigationLink 到 MemoryListView

### 测试覆盖

- `MigrationTests`: v4 表创建 + 列验证 + CASCADE 删除（3 tests）
- `DatabaseManagerMemoryTests`: 8 tests 覆盖 save/fetch/delete/count/ids/type/recent/conversation
- `PromptAssemblerTests`: 四层顺序、labeled context blocks、time-in-current-turn、memory 注入、assemble 集成、TokenBudget 分配与格式验证
- `MemoryExtractionParsingTests`: 13 tests 覆盖 ExtractedMemory JSON 容错解析（大小写 type、字符串 importance、缺失字段、额外字段）+ latestMemoryDate 查询 + StreamDelta usage
- `EmbeddingServiceTests`: bundle 资源存在性、tokenizer 固定长度输出、CoreML 384 维有限归一化向量、compatibility normalization
- `VectorStoreTests`: memory/vector 原子写入、批量事务回滚、sqlite-vec KNN 角色隔离、删除同步、维度校验
- `MemoryManagerRetrievalTests`: 检索异常 fallback 到近期记忆；提取失败不留下半索引记忆；批次失败不推进部分记忆
- `ChatViewModelPromptAssemblyTests`: Chat 发送链路中 fallback 记忆进入 API request；当前输入只进入 API request 一次；API request 保持四层顺序
- 2026-04-30 focused memory/prompt suite 为 27 tests 通过；当前 full suite 为 197 tests / 41 suites，`** TEST SUCCEEDED **`。

### 2026-04-16 修复

- **记忆提取静默失败修复**：替换 `try?` 为 `do/catch` + `os.Logger` 日志
- **ExtractedMemory 解析容错**：`type` 做 `lowercased()` 匹配 + fallback 到 "event"；`importance` 支持 String → Int；缺失字段有默认值
- **增量提取**：不再一刀切跳过已提取对话，通过 `latestMemoryDate` 只提取新消息
- **Conversation 数据刷新**：extractMemories 入口从 DB 重新 fetch 最新 ConversationRecord
- **周期性提取**：每 10 条消息自动触发后台提取
- **提取结果通知**：返回 `[MemoryEntryRecord]`，UI 显示 "已提取 N 条记忆" banner

### 2026-04-30 Memory Vector Reliability 修复

- **资源接线**：`OpenChat/Resources/Models/MultilingualE5Small.mlpackage` 与 `OpenChat/Resources/Models/tokenizer.json` 由 `scripts/generate_xcodeproj.rb` 加入 App Bundle，运行时通过 `Bundle.main` 读取。
- **嵌入模型接线**：`EmbeddingService` 以 CoreML metadata 为准使用固定 `1 x 256` 的 `input_ids` / `attention_mask`，读取 Float16 / Float32 `embeddings` 输出为 384 维 Float 向量后归一化。
- **分词器接线**：`XLMRobertaTokenizer` 读取 `tokenizer.json` 的 Unigram vocab 数组格式，执行 compatibility normalization、metaspace 预处理和固定长度 padding/truncation。
- **向量数据库一致性**：`VectorStore.insert(entry:embedding:)` 与 `VectorStore.insert(entries:)` 在一个 GRDB write transaction 内同时保存 `memory_entry` 和 `memory_embedding`；later vector insert failure 覆盖整批回滚。
- **KNN 角色隔离**：`VectorStore.search(query:characterCardId:limit:)` 使用 sqlite-vec `embedding MATCH ? AND k = ?`，并通过角色卡子查询限定候选记忆。
- **检索可靠降级**：`MemoryManager.retrieveMemories(...)` 在 embedding/model/vector 检索异常时 fallback 到 `retrieveRecentSummary(...)`，Chat 生成链路不再用 `try?` 静默吞掉全部记忆。
