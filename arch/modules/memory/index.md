 # 跨对话记忆模块设计

> 所属层：`Core/Memory/` + `Features/Memory/`
> 依赖：Core/Database（MemoryEntryRecord）, Core/Networking（APIClient）, Shared/Extensions

## 1. 功能范围

- 同一角色跨对话的记忆存储与语义检索
- 本地嵌入模型推理（CoreML MultilingualE5Small）
- 向量存储与 KNN 相似度检索（sqlite-vec）
- 对话结束后自动提取关键事件/摘要作为记忆条目
- 新对话开始时拉取角色近期记忆摘要
- 每次发送消息时检索与当前输入语义相关的记忆
- 记忆条目的查看、搜索与删除管理

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `Core/Memory/EmbeddingService.swift` | CoreML MultilingualE5Small 模型加载与向量推理 |
| `Core/Memory/VectorStore.swift` | sqlite-vec 向量 CRUD 封装（插入 / KNN 检索 / 删除） |
| `Core/Memory/MemoryManager.swift` | 记忆提取与检索的编排层 |
| `Core/Memory/MemoryError.swift` | 记忆模块统一错误类型 |
| `Core/Database/Records/MemoryEntryRecord.swift` | GRDB Record：记忆条目 |
| `Features/Memory/Views/MemoryListView.swift` | 记忆列表界面 |
| `Features/Memory/ViewModels/MemoryListViewModel.swift` | 记忆列表状态管理 |

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
| 分词器 | XLMRobertaTokenizer（`models/tokenizer.json`） |
| 最大输入长度 | 512 tokens |
| 多语言支持 | 是（中 / 英 / 日 等 100+ 语言） |
| 模型文件 | `models/MultilingualE5Small.mlpackage.zip` |

### 4.2 E5 前缀规范

E5 模型要求输入文本添加任务前缀以区分查询与文档：

| 场景 | 前缀 | 示例 |
|---|---|---|
| 存储记忆（passage） | `"passage: "` | `"passage: 玩家在森林中救了一只受伤的精灵"` |
| 检索查询（query） | `"query: "` | `"query: 精灵森林发生了什么"` |

### 4.3 EmbeddingService 接口

```swift
struct EmbeddingService: Sendable {
    /// 将文本转换为 384 维归一化向量
    /// - text: 原始文本（不含前缀）
    /// - isQuery: true 添加 "query: " 前缀，false 添加 "passage: " 前缀
    /// - returns: 归一化的 [Float] 向量，维度 384
    func embed(_ text: String, isQuery: Bool) async throws -> [Float]
}
```

**加载策略**：
- **Lazy 单例**：首次调用 `embed()` 时才加载 CoreML 模型，避免阻塞 App 启动
- **线程安全**：CoreML 推理自动选择最优计算后端（CPU / GPU / ANE）
- **分词**：使用 `models/tokenizer.json`（XLMRobertaTokenizer），超过 512 tokens 的输入自动截断

## 5. 向量存储

### 5.1 集成方式

通过 **SPM 包**引入 sqlite-vec，在 `DatabaseManager` 初始化时加载扩展。

### 5.2 VectorStore 接口

```swift
struct VectorStore: Sendable {
    /// 插入向量嵌入
    func insert(entryId: String, embedding: [Float]) async throws

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

**检索实现**：sqlite-vec 的 KNN 查询与 `memory_entry` 表 JOIN，通过 `characterCardId` 过滤范围。

## 6. 记忆提取流程

### 6.1 触发时机

- 用户离开当前对话（导航到其他页面）
- 用户切换到另一个对话
- App 进入后台

由 `ChatViewModel` 在上述事件发生时调用 `MemoryManager.extractMemories()`。**后台 Task 异步执行，不阻塞 UI**。

### 6.2 提取步骤

```
extractMemories(from conversation):
    1. 检查该对话是否已提取过记忆（避免重复提取）
    2. 从 DB 加载对话全部消息
    3. 如果消息数 < 阈值（如 4 条），跳过提取
    4. 构建提取 prompt（见 6.3）
    5. 调用 APIClient.sendMessage()（非流式，使用对话关联的端点）
    6. 解析 API 返回的 JSON 数组
    7. 对每条提取出的记忆：
       a. 创建 MemoryEntryRecord 并保存到 DB
       b. 调用 EmbeddingService.embed(content, isQuery: false) 生成向量
       c. 调用 VectorStore.insert() 存储向量
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

### 6.4 去重策略

- 提取前检查 `memory_entry` 表中该 `sourceConversationId` 是否已有记录
- 若已存在，跳过提取
- 后续可扩展：对新提取的记忆与已有记忆做向量相似度比较，去除高度重复条目

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
    3. 过滤掉 distance 超过阈值的结果（相关度过低）
    4. 从 DB 加载对应的 MemoryEntryRecord
    5. 与 retrieveRecentSummary() 结果合并去重
    6. 结果传入 PromptAssembler
```

### 7.3 注入方式

检索到的记忆作为 `PromptSegment.memoryEntry(MemoryEntryRecord)` 注入 prompt：
- **位置**：世界书条目（before_history）之后、示例对话之前
- **role**: `"system"`
- **priority**: 85（高于 exampleDialog:75，低于世界书条目最大值）
- **token 预算**: 上限为 totalBudget × 10%
- **格式**: 每条记忆作为独立的 system 消息注入

## 8. MemoryManager 接口

```swift
struct MemoryManager: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let apiClient: APIClient

    /// 从对话中提取记忆（后台异步调用）
    func extractMemories(from conversation: ConversationRecord) async throws

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

记忆系统的所有错误**不阻断聊天主流程**。提取或检索失败时静默降级（不注入记忆），仅记录日志。

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
| `Core/PromptEngine` | 检索到的记忆作为 `PromptSegment.memoryEntry` 注入 prompt，token 预算上限 10% |
| `Features/Chat` | `ChatViewModel` 在发送消息时调用 `retrieveMemories()`；在离开对话时调用 `extractMemories()` |
| `Core/Database` | `MemoryEntryRecord` CRUD + `memory_embedding` sqlite-vec 虚拟表操作 |
| `Core/Networking` | 记忆提取时调用 `APIClient.sendMessage()` 请求 LLM 提取结构化记忆 |
| `Features/CharacterCard` | 角色详情页提供记忆列表入口 |

## 12. 设计决策

1. **摘要/事件级粒度**：不存储原始消息向量（量大且噪声高），而是提取关键事件/摘要后向量化，质量更高
2. **本地嵌入模型**：使用 CoreML 在设备端推理，无需网络请求，保护用户隐私
3. **sqlite-vec**：复用已有的 SQLite 基础设施，无需引入独立的向量数据库
4. **10% token 预算**：避免记忆占用过多上下文空间，保持当前对话质量
5. **静默降级**：记忆系统故障不应影响核心聊天功能
6. **对话级提取**：在对话结束时一次性提取，避免每条消息都调用 API 提取带来的成本和延迟

## 13. 实现证据

> Phase 7 实现完成（对应 roadmap.md）

### 已实现文件

| 设计文件 | 实现位置 | 说明 |
|---|---|---|
| EmbeddingService | `Core/Memory/EmbeddingService.swift` | `final class: @unchecked Sendable`，NSLock 保护 lazy MLModel + XLMRobertaTokenizer |
| VectorStore | `Core/Memory/VectorStore.swift` | sqlite-vec 封装，insert/search/delete/deleteAll |
| MemoryManager | `Core/Memory/MemoryManager.swift` | struct Sendable，提取+检索编排 |
| MemoryError | `Core/Memory/MemoryError.swift` | MemoryType enum + MemoryError enum |
| MemoryEntryRecord | `Core/Database/Records/MemoryEntryRecord.swift` | GRDB FetchableRecord + PersistableRecord |
| DatabaseManager+Memory | `Core/Database/DatabaseManager+Memory.swift` | 8 个 CRUD 方法 |
| MemoryListView | `Features/CharacterCard/Views/MemoryListView.swift` | 搜索+删除+清空 UI |
| MemoryListViewModel | `Features/CharacterCard/ViewModels/MemoryListViewModel.swift` | @Observable MVVM |
| sqlite-vec SPM | `Packages/SqliteVec/` | 本地 C 包，v0.1.9 |
| 迁移 v4 | `Core/Database/Migrations.swift` | memory_entry 表 + memory_embedding vec0 虚拟表 |

### 关键集成点

- `DependencyContainer` → 注入 `MemoryManager`（含 EmbeddingService + VectorStore）
- `ChatViewModel` → 持有 `memoryManager`，发送消息时 `retrieveMemories()`，离开对话时 `triggerMemoryExtraction()`
- `PromptAssembler` → `memories: [MemoryEntryRecord]` 参数，`makeMemoryMessageContent()` 格式化
- `TokenBudget` → `memoryBudget`（remaining × 15%）
- `PromptSegment` → `.timeContext(String)` + `.memoryEntry(MemoryEntryRecord)`
- `CharacterCardDetailView` → Memory section 显示计数 + NavigationLink 到 MemoryListView

### 测试覆盖

- `MigrationTests`: v4 表创建 + 列验证 + CASCADE 删除（3 tests）
- `DatabaseManagerMemoryTests`: 8 tests 覆盖 save/fetch/delete/count/ids/type/recent/conversation
- `PromptAssemblerTests`: timeContext 注入 + memory 注入 + assemble 集成 + TokenBudget 分配 + 格式验证（5 tests）
- 全部 35 tests 通过
