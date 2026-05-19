# 数据模型定义

## 概述

持久层使用 **GRDB.swift** 操作 SQLite。所有表定义为 GRDB `Record` 子类（或实现 `FetchableRecord + PersistableRecord`）。本文档定义所有表结构、字段、约束、关系及迁移策略。

---

## 表结构

### 1. api_endpoint — API 端点配置

存储用户添加的 OpenAI 兼容 API 端点。端点仅定义 URL 和 API Key 的组合，模型配置通过 `endpoint_model` 表独立管理。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| name | TEXT | NOT NULL | 显示名称，如 "本地 Llama" |
| baseURL | TEXT | NOT NULL | 接口基础地址，如 `http://localhost:8080/v1` |
| apiKey | TEXT | | API 密钥（可选，本地模型可为空） |
| isDefault | INTEGER | NOT NULL, DEFAULT 0 | 是否为默认端点（布尔值） |
| createdAt | TEXT | NOT NULL | ISO 8601 时间戳 |
| updatedAt | TEXT | NOT NULL | ISO 8601 时间戳 |

**Swift Record**:
```swift
struct APIEndpointRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "api_endpoint"
    var id: String           // UUID().uuidString
    var name: String
    var baseURL: String
    var apiKey: String?
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    static let models = hasMany(EndpointModelRecord.self)
}
```

---

### 1b. endpoint_model — 端点可用模型

存储每个端点的可用模型列表，包含模型级别的上下文窗口和 API 模式配置。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| endpointId | TEXT | NOT NULL, FK → api_endpoint.id | 所属端点 |
| modelId | TEXT | NOT NULL | 模型标识符，如 `gpt-4o` |
| maxContextTokens | INTEGER | NOT NULL, DEFAULT 4096 | 该模型的最大上下文 token 数 |
| apiMode | TEXT | NOT NULL, DEFAULT 'chatCompletions' | API 模式：`chatCompletions` / `responses` |
| providerDialect | TEXT | NOT NULL, DEFAULT 'openAICompatible' | 供应商方言：`openAICompatible` / `deepSeekV4` |
| isDefault | BOOLEAN | NOT NULL, DEFAULT 0 | 是否为该端点的默认模型 |
| isManual | BOOLEAN | NOT NULL, DEFAULT 0 | 是否为用户手动添加（不被 API 拉取覆盖） |
| createdAt | TEXT | NOT NULL | ISO 8601 时间戳 |

**约束**：
- 外键：`endpointId` → `api_endpoint(id)` ON DELETE CASCADE
- 唯一约束：`UNIQUE(endpointId, modelId)`

**Swift Record**:
```swift
struct EndpointModelRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "endpoint_model"
    var id: String
    var endpointId: String
    var modelId: String
    var maxContextTokens: Int
    var apiMode: String          // "chatCompletions" | "responses"
    var providerDialect: String  // "openAICompatible" | "deepSeekV4"
    var isDefault: Bool
    var isManual: Bool
    var createdAt: Date

    static let endpoint = belongsTo(APIEndpointRecord.self)
}
```

---

### 2. character_card — 角色卡

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| name | TEXT | NOT NULL | 角色名称 |
| avatar | BLOB | | 角色头像（PNG/JPEG 二进制，可选） |
| personality | TEXT | | 性格描述 |
| appearance | TEXT | | 外貌描述 |
| physique | TEXT | | 身材描述 |
| speechStyle | TEXT | | 语调/说话风格 |
| backstory | TEXT | | 背景故事 |
| systemPrompt | TEXT | | 角色专属 system prompt（可覆盖默认） |
| scenario | TEXT | | 默认场景设定 |
| exampleDialogs | TEXT | | 示例对话（JSON 数组格式） |
| creatorNotes | TEXT | | 创建者备注（不进入 prompt） |
| tags | TEXT | | 标签（JSON 数组，用于筛选） |
| worldBookId | TEXT | FK → world_book.id, ON DELETE SET NULL | 所属世界书（可选） |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**外键**：`worldBookId` → `world_book(id)` ON DELETE SET NULL

**Swift Record**:
```swift
struct CharacterCardRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "character_card"
    var id: String
    var name: String
    var avatar: Data?
    var personality: String?
    var appearance: String?
    var physique: String?
    var speechStyle: String?
    var backstory: String?
    var systemPrompt: String?
    var scenario: String?
    var exampleDialogs: String?      // JSON: [{"role":"user","content":"..."},...]
    var creatorNotes: String?
    var tags: String?                // JSON: ["fantasy","sci-fi"]
    var worldBookId: String?         // 所属世界书
    var createdAt: Date
    var updatedAt: Date

    static let worldBook = belongsTo(WorldBookRecord.self)
}
```

---

### 3. world_book — 世界书

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| name | TEXT | NOT NULL | 世界书名称 |
| description | TEXT | | 世界书简介 |
| isEnabled | INTEGER | NOT NULL, DEFAULT 1 | 是否启用 |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**Swift Record**:
```swift
struct WorldBookRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "world_book"
    var id: String
    var name: String
    var description: String?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

---

### 4. world_book_entry — 世界书条目

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| worldBookId | TEXT | NOT NULL, FK → world_book.id | 所属世界书 |
| title | TEXT | NOT NULL | 条目标题（如 "精灵族"） |
| content | TEXT | NOT NULL | 条目正文（描述性文本，将注入 prompt） |
| keywords | TEXT | NOT NULL | 触发关键词（JSON 数组，如 `["精灵","elf","耳朵"]`） |
| priority | INTEGER | NOT NULL, DEFAULT 50 | 注入优先级（0-100，越大越优先） |
| isEnabled | INTEGER | NOT NULL, DEFAULT 1 | 是否启用 |
| position | TEXT | NOT NULL, DEFAULT 'before_history' | 旧注入位置兼容字段：`before_history` / `after_system`；当前 PromptAssembler 最终统一注入 `[World Book Entries]` block |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**外键**：`worldBookId` → `world_book(id)` ON DELETE CASCADE

**Swift Record**:
```swift
struct WorldBookEntryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "world_book_entry"
    var id: String
    var worldBookId: String
    var title: String
    var content: String
    var keywords: String             // JSON: ["精灵","elf"]
    var priority: Int
    var isEnabled: Bool
    var position: String             // compatibility: "before_history" | "after_system"
    var createdAt: Date
    var updatedAt: Date

    static let worldBook = belongsTo(WorldBookRecord.self)
}
```

**向量嵌入（Phase A-D 已实现）**：世界书条目的向量存储在 sqlite-vec 虚拟表 `world_book_entry_embedding` 中（见迁移 v15），索引审计状态存储在 `world_book_entry_embedding_meta` 中（见迁移 v16）。Phase B 提供 stable embedding text、content hash、existing-entry rebuild/backfill indexer 和 `WorldBookVectorStore` KNN 能力；Phase C 通过 `WorldBookSource` 把 keyword + semantic 融合结果接入 Chat prompt，仍输出兼容的 `[World Book Entries]` block；Phase D 已把 save/import/delete/eraseAllData 与 Data Management 手动 rebuild 接入 indexer / cleanup 链路。

---

### 4b. world_book_entry_embedding — 世界书条目向量

sqlite-vec virtual table，存储世界书条目的 384 维 embedding。

```sql
CREATE VIRTUAL TABLE world_book_entry_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

说明：

- `entry_id` 对应 `world_book_entry.id`，但 sqlite-vec virtual table 不依赖 FK cascade。
- `WorldBookVectorStore.search(query:worldBookId:limit:)` 必须先把候选限定到当前 `worldBookId` 且 `isEnabled = 1` 的条目，再执行 KNN。
- 删除 entry/worldBook 时必须显式清理 virtual table；Phase D 已将 `DatabaseManager.deleteWorldBookEntry(...)`、`deleteWorldBook(...)` 和 `eraseAllData(...)` 接入 `world_book_entry_embedding` / meta cleanup，不能只依赖 FK cascade。
- Phase B `WorldBookEmbeddingIndexer` 成功 index 时会在同一 `DatabaseManager.write` 内写入 vector row 和 `indexed` meta；失败时写 `failed` meta，不删除用户的 `world_book_entry`。

---

### 4c. world_book_entry_embedding_meta — 世界书条目向量元数据

普通表，用于可审计增量重建和已导入世界书 backfill。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| entryId | TEXT | PK, FK → world_book_entry.id, ON DELETE CASCADE | 对应世界书条目 |
| contentHash | TEXT | NOT NULL | title / keywords / content 规范化后的内容 hash |
| embeddingModel | TEXT | NOT NULL | 生成 embedding 的模型标识 |
| embeddingDimension | INTEGER | NOT NULL | 当前为 384 |
| status | TEXT | NOT NULL | `indexed` / `needs_rebuild` / `failed` |
| embeddedAt | TEXT | | 成功索引时间 |
| lastAttemptAt | TEXT | | 最近一次索引尝试时间 |
| lastError | TEXT | | 最近失败原因 |
| updatedAt | TEXT | NOT NULL | 元数据更新时间 |

**索引**：

- `idx_world_book_entry_embedding_meta_status`
- `idx_world_book_entry_embedding_meta_model`

**Swift Record**：

```swift
struct WorldBookEntryEmbeddingMetaRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "world_book_entry_embedding_meta"
    var entryId: String
    var contentHash: String
    var embeddingModel: String
    var embeddingDimension: Int
    var status: String
    var embeddedAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?
    var updatedAt: Date
}
```

---

### 5. conversation — 会话

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| title | TEXT | NOT NULL | 会话标题（可自动生成或用户编辑） |
| characterCardId | TEXT | FK → character_card.id | 绑定的角色卡（可选，世界书通过角色卡间接关联） |
| apiEndpointId | TEXT | FK → api_endpoint.id | 使用的 API 端点 |
| modelName | TEXT | | 会话使用的模型名称（字符串引用，非 FK） |
| contextStrategy | TEXT | NOT NULL, DEFAULT 'truncation' | 上下文策略：`truncation` / `compression` |
| compressionMode | TEXT | NOT NULL, DEFAULT 'standard' | 压缩模式：`standard` / `highIntelligence`，仅在 compression 策略下生效 |
| customScenario | TEXT | | 会话专属场景覆盖（优先于角色卡场景） |
| modelParameters | TEXT | | 模型参数覆盖（JSON: `{"temperature":0.8,...}`） |
| slowPlotMode | INTEGER | NOT NULL, DEFAULT 1 | 慢速剧情推进模式开关（beta） |
| isTitleGenerated | INTEGER | NOT NULL, DEFAULT 0 | 标题是否已由模型生成或用户确认，避免重复自动改名 |
| isPinned | INTEGER | NOT NULL, DEFAULT 0 | 是否置顶 |
| lastExtractedSortOrder | INTEGER | | 上次记忆提取处理到的消息 sortOrder（用于增量提取 cutoff） |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**Swift Record**:
```swift
struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversation"
    var id: String
    var title: String
    var characterCardId: String?
    var apiEndpointId: String?
    var modelName: String?           // 动态选择的模型名称
    var contextStrategy: String      // "truncation" | "compression"
    var compressionMode: String      // "standard" | "highIntelligence"
    var customScenario: String?
    var modelParameters: String?     // JSON
    var slowPlotMode: Bool
    var isTitleGenerated: Bool
    var isPinned: Bool
    var lastExtractedSortOrder: Int?
    var createdAt: Date
    var updatedAt: Date

    static let characterCard = belongsTo(CharacterCardRecord.self)
    static let apiEndpoint = belongsTo(APIEndpointRecord.self)
    static let messages = hasMany(MessageRecord.self)
    static let compressionCheckpoints = hasMany(CompressionCheckpointRecord.self)
}
```

---

### 6. message — 消息

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| conversationId | TEXT | NOT NULL, FK → conversation.id | 所属会话 |
| role | TEXT | NOT NULL | `system` / `user` / `assistant` |
| content | TEXT | NOT NULL | 消息文本内容 |
| tokenCount | INTEGER | | 该消息的估算 token 数 |
| isCompressed | INTEGER | NOT NULL, DEFAULT 0 | 是否为压缩后的摘要消息 |
| originalContent | TEXT | | 压缩前的原始内容（仅压缩消息有值） |
| sortOrder | INTEGER | NOT NULL | 排序序号（时间顺序递增） |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| reasoningContent | TEXT | | 模型返回的角色思考链，例如 DeepSeek V4 `reasoning_content` |
| stageId | TEXT | FK → stage.id, ON DELETE SET NULL | Stage 消息来源（可选） |
| speakerKind | TEXT | | 发言者类型：`participant` / `director` / `system` |
| speakerId | TEXT | | Stage participant id 或未来 director/system id |
| speakerName | TEXT | | 消息显示名快照，避免角色重命名影响历史展示 |

**外键**：
- `conversationId` → `conversation(id)` ON DELETE CASCADE
- `stageId` → `stage(id)` ON DELETE SET NULL

**Swift Record**:
```swift
struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "message"
    var id: String
    var conversationId: String
    var role: String                 // "system" | "user" | "assistant"
    var content: String
    var tokenCount: Int?
    var isCompressed: Bool
    var originalContent: String?
    var sortOrder: Int
    var createdAt: Date
    var reasoningContent: String?
    var stageId: String?
    var speakerKind: String?
    var speakerId: String?
    var speakerName: String?

    static let conversation = belongsTo(ConversationRecord.self)

    // 普通 prompt 历史不回传 reasoningContent。
    var chatMessage: ChatMessage { ChatMessage(role: role, content: content) }
}
```

---

### 6a. stage — 舞台

一个 Stage 绑定到一个 Conversation，用于保存导演模式、多角色参与和舞台级指令。当前最小实现是一会话最多一个 Stage。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| conversationId | TEXT | NOT NULL, UNIQUE, FK → conversation.id | 所属会话 |
| title | TEXT | | 舞台标题，当前默认来自 conversation title |
| directorMode | TEXT | NOT NULL, DEFAULT 'silent' | `silent` / `agent` / `userControlled` |
| isEnabled | BOOLEAN | NOT NULL, DEFAULT 1 | 是否启用 Stage |
| createdAt | DATETIME | NOT NULL | 创建时间 |
| updatedAt | DATETIME | NOT NULL | 更新时间 |

**外键**：
- `conversationId` → `conversation(id)` ON DELETE CASCADE

**索引 / 约束**：
- `UNIQUE(conversationId)`
- `idx_stage_conversationId`

**Swift Record**：
```swift
struct StageRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage"
    var id: String
    var conversationId: String
    var title: String?
    var directorMode: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    static let conversation = belongsTo(ConversationRecord.self)
    static let participants = hasMany(StageParticipantRecord.self)
    static let instructions = hasMany(StageInstructionRecord.self)
}
```

---

### 6b. stage_participant — 舞台参与角色

保存一个 Stage 中绑定的角色卡和本地显示名快照。当前 runtime 只把 `present + isActive` 的 participant 作为候选 speaker。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| stageId | TEXT | NOT NULL, FK → stage.id | 所属舞台 |
| characterCardId | TEXT | NOT NULL, FK → character_card.id | 绑定角色卡 |
| displayName | TEXT | NOT NULL | 舞台内显示名快照 |
| visibility | TEXT | NOT NULL, DEFAULT 'present' | `present` / `hidden` |
| isActive | BOOLEAN | NOT NULL, DEFAULT 1 | 是否可作为当前 speaker |
| sortOrder | INTEGER | NOT NULL | 舞台内排序 |
| createdAt | DATETIME | NOT NULL | 创建时间 |
| updatedAt | DATETIME | NOT NULL | 更新时间 |

**外键**：
- `stageId` → `stage(id)` ON DELETE CASCADE
- `characterCardId` → `character_card(id)` ON DELETE CASCADE

**索引 / 约束**：
- `UNIQUE(stageId, characterCardId)`
- `idx_stage_participant_stageId(stageId, sortOrder)`
- `idx_stage_participant_characterCardId`

**Swift Record**：
```swift
struct StageParticipantRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage_participant"
    var id: String
    var stageId: String
    var characterCardId: String
    var displayName: String
    var visibility: String
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    static let stage = belongsTo(StageRecord.self)
    static let characterCard = belongsTo(CharacterCardRecord.self)
}
```

---

### 6c. stage_instruction — 舞台指令

保存用户或未来 Director agent 产生的舞台级指令。当前用户导演输入会写入该表，且不写入普通 `message` history。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| stageId | TEXT | NOT NULL, FK → stage.id | 所属舞台 |
| source | TEXT | NOT NULL, DEFAULT 'user' | `user` / `directorAgent` / `systemDefault` |
| content | TEXT | NOT NULL | 指令正文 |
| visibility | TEXT | NOT NULL, DEFAULT 'hiddenFromCharacters' | `hiddenFromCharacters` / `visibleToParticipants` / `debugOnly` |
| createdAt | DATETIME | NOT NULL | 创建时间 |

**外键**：
- `stageId` → `stage(id)` ON DELETE CASCADE

**索引**：
- `idx_stage_instruction_stageId(stageId, createdAt)`

**Swift Record**：
```swift
struct StageInstructionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage_instruction"
    var id: String
    var stageId: String
    var source: String
    var content: String
    var visibility: String
    var createdAt: Date

    static let stage = belongsTo(StageRecord.self)
}
```

---

### 6d. conversation_compression_checkpoint — 会话压缩检查点

存储 Codex 风格的持久化上下文压缩 checkpoint。checkpoint 不替换或删除原始 `message` 记录；prompt 侧读取最近有效 checkpoint，并拼接 checkpoint 后的真实 message history。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| conversationId | TEXT | NOT NULL, FK → conversation.id | 所属会话 |
| parentCheckpointId | TEXT | FK → conversation_compression_checkpoint.id | 上一个 checkpoint，可空 |
| sourceStartSortOrder | INTEGER | NOT NULL | 本摘要覆盖的首条消息 sortOrder |
| sourceEndSortOrder | INTEGER | NOT NULL | 本摘要覆盖的末条消息 sortOrder |
| sourceHash | TEXT | NOT NULL | 覆盖消息内容的 SHA256 hash |
| summary | TEXT | NOT NULL | 压缩摘要 |
| summaryTokenCount | INTEGER | NOT NULL | 摘要估算 token |
| endpointId | TEXT | FK → api_endpoint.id, ON DELETE SET NULL | 生成摘要使用的端点 |
| modelName | TEXT | NOT NULL | 生成摘要使用的模型 |
| modelMaxContextTokens | INTEGER | NOT NULL | 生成时模型声明上下文 |
| effectiveCompactWindowTokens | INTEGER | NOT NULL | 生成时采用的事实压缩窗口 |
| autoCompactTokenLimit | INTEGER | NOT NULL | 生成时采用的自动压缩阈值 |
| createdAt | TEXT | NOT NULL | ISO 8601 |

**外键**：
- `conversationId` → `conversation(id)` ON DELETE CASCADE
- `parentCheckpointId` → `conversation_compression_checkpoint(id)` ON DELETE SET NULL
- `endpointId` → `api_endpoint(id)` ON DELETE SET NULL

**约束**：
- 唯一约束：`UNIQUE(conversationId, sourceStartSortOrder, sourceEndSortOrder, sourceHash)`
- 索引：`idx_compression_checkpoint_conversationId`
- 索引：`idx_compression_checkpoint_sourceEnd(conversationId, sourceEndSortOrder)`

**Swift Record**:
```swift
struct CompressionCheckpointRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversation_compression_checkpoint"
    var id: String
    var conversationId: String
    var parentCheckpointId: String?
    var sourceStartSortOrder: Int
    var sourceEndSortOrder: Int
    var sourceHash: String
    var summary: String
    var summaryTokenCount: Int
    var endpointId: String?
    var modelName: String
    var modelMaxContextTokens: Int
    var effectiveCompactWindowTokens: Int
    var autoCompactTokenLimit: Int
    var createdAt: Date

    static let conversation = belongsTo(ConversationRecord.self)
}
```

---

### 7. memory_entry — 记忆条目

存储角色跨对话的记忆（摘要/事件/事实/关系），用于语义检索后注入 prompt。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| characterCardId | TEXT | NOT NULL, FK → character_card.id | 所属角色卡 |
| sourceConversationId | TEXT | FK → conversation.id | 来源对话（可选，对话删除后置 NULL） |
| content | TEXT | NOT NULL | 记忆原文（摘要 / 事件描述） |
| memoryType | TEXT | NOT NULL | `event` / `fact` / `relationship` / `summary` |
| importance | INTEGER | NOT NULL, DEFAULT 50 | 重要性评分（0-100） |
| createdAt | TEXT | NOT NULL | ISO 8601 |
| updatedAt | TEXT | NOT NULL | ISO 8601 |

**外键**：
- `characterCardId` → `character_card(id)` ON DELETE CASCADE
- `sourceConversationId` → `conversation(id)` ON DELETE SET NULL

**Swift Record**:
```swift
struct MemoryEntryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "memory_entry"
    var id: String
    var characterCardId: String
    var sourceConversationId: String?
    var content: String
    var memoryType: String           // "event" | "fact" | "relationship" | "summary"
    var importance: Int
    var createdAt: Date
    var updatedAt: Date

    static let characterCard = belongsTo(CharacterCardRecord.self)
    static let sourceConversation = belongsTo(ConversationRecord.self)
}
```

**向量嵌入**：记忆条目的向量存储在 sqlite-vec 虚拟表 `memory_embedding` 中（见迁移 v4）。

---

### 7b. memory_entry_link — 记忆关系

记录 reflect observation 与来源记忆之间的 based-on 关系。当前 Phase 5 只在用户确认手动整理 draft 后写入 `summarizes` links；原始 `memory_entry` 不会被自动删除、覆盖或替代。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| fromMemoryEntryId | TEXT | NOT NULL, FK -> memory_entry.id | 新 observation / 关系来源 |
| toMemoryEntryId | TEXT | NOT NULL, FK -> memory_entry.id | 被引用的来源记忆 |
| relation | TEXT | NOT NULL | `summarizes` / `duplicates` / `reinforces` |
| createdAt | TEXT | NOT NULL | ISO 8601 |

**外键**：
- `fromMemoryEntryId` -> `memory_entry(id)` ON DELETE CASCADE
- `toMemoryEntryId` -> `memory_entry(id)` ON DELETE CASCADE

**索引**：
- `idx_memory_entry_link_fromMemoryEntryId`
- `idx_memory_entry_link_toMemoryEntryId`
- `idx_memory_entry_link_relation`

**Swift Record**:
```swift
struct MemoryEntryLinkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "memory_entry_link"
    var id: String
    var fromMemoryEntryId: String
    var toMemoryEntryId: String
    var relation: MemoryEntryLinkRelation
    var createdAt: Date
}
```

---

## 实体关系图（文字 ER）

```
api_endpoint 1 ──── 0..* endpoint_model
api_endpoint 1 ──── 0..* conversation
character_card 1 ──── 0..* conversation
world_book 1 ──── 0..* character_card
world_book 1 ──── 0..* world_book_entry
character_card 1 ──── 0..* memory_entry
memory_entry 1 ──── 0..* memory_entry_link
conversation 1 ──── 0..* memory_entry
conversation 1 ──── 0..* message
conversation 1 ──── 0..* conversation_compression_checkpoint
conversation 1 ──── 0..1 stage
stage 1 ──── 0..* stage_participant
stage 1 ──── 0..* stage_instruction
stage 1 ──── 0..* message
character_card 1 ──── 0..* stage_participant
```

关系说明：
- 一个 `api_endpoint` 包含多个 `endpoint_model`（可用模型列表）
- 一个 `conversation` 可选绑定一个 `character_card`、一个 `api_endpoint`
- `conversation.modelName` 为字符串引用（非 FK），记录该对话使用的模型名称
- 一个 `character_card` 可选归属于一个 `world_book`（世界书通过角色卡间接关联到对话）
- 一个 `world_book` 包含多个 `world_book_entry`
- 一个 `character_card` 关联多条 `memory_entry`（跨对话记忆）
- 一条 `memory_entry` 可通过 `memory_entry_link` 指向其他 memory，保留 reflect observation 的 based-on 来源
- 一个 `conversation` 包含多条 `message`
- 一个 `conversation` 包含多条 `conversation_compression_checkpoint`，用于复用旧历史压缩摘要
- 一个 `conversation` 最多包含一个 `stage`
- 一个 `stage` 包含多个 `stage_participant` 和 `stage_instruction`
- 一个 `stage` 可关联多条带 speaker metadata 的 `message`
- 一个 `conversation` 可关联多条 `memory_entry`（记忆来源）
- 删除 `conversation` 时级联删除其所有 `message`
- 删除 `conversation` 时级联删除其所有 `conversation_compression_checkpoint`
- 删除 `conversation` 时级联删除其 `stage`，并级联删除 stage participants / instructions
- 删除 `stage` 时，关联 `message.stageId` 置 NULL，保留消息文本和 speaker 快照
- 删除 `api_endpoint` 时，关联 `conversation_compression_checkpoint` 的 `endpointId` 置 NULL
- 删除 `world_book` 时级联删除其所有 `world_book_entry`
- 删除 `character_card` 时级联删除其所有 `memory_entry`
- 删除 `character_card` 时级联删除对应 `stage_participant`
- 删除 `memory_entry` 时级联删除以它为 from/to endpoint 的 `memory_entry_link`
- 删除 `character_card` / `api_endpoint` 时，关联 `conversation` 的外键置 NULL
- 删除 `api_endpoint` 时，级联删除其所有 `endpoint_model`
- 删除 `world_book` 时，关联 `character_card` 的 `worldBookId` 置 NULL
- 删除 `conversation` 时，关联 `memory_entry` 的 `sourceConversationId` 置 NULL

---

## 迁移策略

使用 GRDB 的 `DatabaseMigrator` 管理版本迁移：

```swift
var migrator = DatabaseMigrator()

migrator.registerMigration("v1_initial") { db in
    // 按依赖顺序建表：api_endpoint → character_card → world_book
    // → world_book_entry → conversation → message

    try db.create(table: Historical.apiEndpointTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("name", .text).notNull()
        t.column("baseURL", .text).notNull()
        t.column("apiKey", .text)
        t.column("modelName", .text).notNull()
        t.column("maxContextTokens", .integer).notNull().defaults(to: 4096)
        t.column("isDefault", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: Historical.characterCardTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("name", .text).notNull()
        t.column("avatar", .blob)
        t.column("personality", .text)
        t.column("appearance", .text)
        t.column("physique", .text)
        t.column("speechStyle", .text)
        t.column("backstory", .text)
        t.column("systemPrompt", .text)
        t.column("scenario", .text)
        t.column("exampleDialogs", .text)
        t.column("creatorNotes", .text)
        t.column("tags", .text)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: Historical.worldBookTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("name", .text).notNull()
        t.column("description", .text)
        t.column("isEnabled", .boolean).notNull().defaults(to: true)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: Historical.worldBookEntryTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("worldBookId", .text).notNull()
            .references(Historical.worldBookTable, onDelete: .cascade)
        t.column("title", .text).notNull()
        t.column("content", .text).notNull()
        t.column("keywords", .text).notNull()
        t.column("priority", .integer).notNull().defaults(to: 50)
        t.column("isEnabled", .boolean).notNull().defaults(to: true)
        t.column("position", .text).notNull().defaults(to: Historical.worldBookEntryBeforeHistory)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: Historical.conversationTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("title", .text).notNull()
        t.column("characterCardId", .text)
            .references(Historical.characterCardTable, onDelete: .setNull)
        t.column("apiEndpointId", .text)
            .references(Historical.apiEndpointTable, onDelete: .setNull)
        t.column("contextStrategy", .text).notNull().defaults(to: Historical.contextStrategyTruncation)
        t.column("customScenario", .text)
        t.column("modelParameters", .text)
        t.column("isPinned", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: Historical.messageTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("conversationId", .text).notNull()
            .references(Historical.conversationTable, onDelete: .cascade)
        t.column("role", .text).notNull()
        t.column("content", .text).notNull()
        t.column("tokenCount", .integer)
        t.column("isCompressed", .boolean).notNull().defaults(to: false)
        t.column("originalContent", .text)
        t.column("sortOrder", .integer).notNull()
        t.column("createdAt", .datetime).notNull()
    }
}
```

### 索引

```swift
// v1_initial 迁移中追加索引
try db.create(index: "idx_message_conversationId", on: Historical.messageTable, columns: ["conversationId"])
try db.create(index: "idx_message_sortOrder", on: Historical.messageTable, columns: ["conversationId", "sortOrder"])
try db.create(index: "idx_world_book_entry_worldBookId", on: Historical.worldBookEntryTable, columns: ["worldBookId"])
try db.create(index: "idx_conversation_characterCardId", on: Historical.conversationTable, columns: ["characterCardId"])
try db.create(index: "idx_conversation_updatedAt", on: Historical.conversationTable, columns: ["updatedAt"])
```

### v2_world_book_character_card

角色卡归属世界书：为 `character_card` 表添加 `worldBookId` 外键。

```swift
migrator.registerMigration("v2_world_book_character_card") { db in
    try db.alter(table: Historical.characterCardTable) { t in
        t.add(column: "worldBookId", .text)
            .references(Historical.worldBookTable, onDelete: .setNull)
    }
    try db.create(index: "idx_character_card_worldBookId",
                  on: Historical.characterCardTable, columns: ["worldBookId"])
}
```

### v3_remove_world_book_from_conversation

对话不再直接关联世界书，世界书通过角色卡间接关联。

```swift
migrator.registerMigration("v3_remove_world_book_from_conversation") { db in
    // 数据迁移：将 conversation.worldBookId 写入对应 character_card.worldBookId
    try db.execute(sql: """
        UPDATE character_card SET worldBookId = (
            SELECT c.worldBookId FROM conversation c
            WHERE c.characterCardId = character_card.id
            AND c.worldBookId IS NOT NULL
            LIMIT 1
        )
        WHERE worldBookId IS NULL
    """)

    // iOS 17+ SQLite 原生支持 ALTER TABLE DROP COLUMN
    try db.alter(table: Historical.conversationTable) { t in
        t.drop(column: "worldBookId")
    }
}
```

### v4_create_memory_tables

创建记忆条目表和 sqlite-vec 向量嵌入虚拟表。

```swift
migrator.registerMigration("v4_create_memory_tables") { db in
    try db.create(table: Historical.memoryEntryTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("characterCardId", .text).notNull()
            .references(Historical.characterCardTable, onDelete: .cascade)
        t.column("sourceConversationId", .text)
            .references(Historical.conversationTable, onDelete: .setNull)
        t.column("content", .text).notNull()
        t.column("memoryType", .text).notNull()
        t.column("importance", .integer).notNull().defaults(to: 50)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(index: "idx_memory_entry_characterCardId",
                  on: Historical.memoryEntryTable, columns: ["characterCardId"])
    try db.create(index: "idx_memory_entry_sourceConversationId",
                  on: Historical.memoryEntryTable, columns: ["sourceConversationId"])

    // sqlite-vec 虚拟表：存储 384 维嵌入向量
    try db.execute(sql: """
        CREATE VIRTUAL TABLE \(Historical.memoryEmbeddingTable) USING vec0(
            entry_id TEXT PRIMARY KEY,
            embedding float[384]
        )
    """)
}
```

### 后续版本迁移原则

- 每个数据库变更注册一个新的 `migration`，命名格式 `v{N}_{description}`
- 只追加迁移，不修改已有迁移
- 迁移中使用 `ALTER TABLE` 添加列而非重建表
- 迁移代码中不引用 Record 类型，使用原始 SQL 或 GRDB DDL API

### Migration 源码约束

- migration 中使用迁移本地常量记录历史表名和默认值，例如 `Historical.apiEndpointTable`、`Historical.apiModeChatCompletions`。
- migration 不引用 `Record.databaseTableName`、`APIMode.*.rawValue`、`WorldBookEntryPosition.*.rawValue`、`ContextStrategy.*.rawValue`，避免未来 runtime 重命名破坏旧迁移。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 中的 `test_migrations_do_not_reference_runtime_record_or_enum_symbols` 保护该约束。

### v5_addApiMode

为 `api_endpoint` 表添加 `apiMode` 列，支持 Chat Completions 和 Responses API 两种模式切换。

```swift
migrator.registerMigration("v5_addApiMode") { db in
    try db.alter(table: Historical.apiEndpointTable) { t in
        t.add(column: "apiMode", .text).notNull().defaults(to: Historical.apiModeChatCompletions)
    }
}
```

### v6_add_reasoning_content

为 `message` 添加 `reasoningContent`，保存 DeepSeek V4 等模型返回的角色思考链。该字段用于展示与持久化；普通 prompt 历史通过 `MessageRecord.chatMessage` 仅回传 `role` 与 `content`，不回传历史 `reasoningContent`。

```swift
migrator.registerMigration("v6_add_reasoning_content") { db in
    try db.alter(table: Historical.messageTable) { t in
        t.add(column: "reasoningContent", .text)
    }
}
```

### v8_endpoint_model_decoupling

将模型配置从端点表解耦到独立的 `endpoint_model` 表。端点仅保留 URL + API Key 组合，模型（含 maxContextTokens、apiMode）独立管理。对话通过 `modelName` 字符串记录所选模型。

```swift
migrator.registerMigration("v8_endpoint_model_decoupling") { db in
    // 1. 创建 endpoint_model 表
    try db.create(table: Historical.endpointModelTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("endpointId", .text).notNull()
            .references(Historical.apiEndpointTable, onDelete: .cascade)
        t.column("modelId", .text).notNull()
        t.column("maxContextTokens", .integer).notNull().defaults(to: 4096)
        t.column("apiMode", .text).notNull().defaults(to: Historical.apiModeChatCompletions)
        t.column("isDefault", .boolean).notNull().defaults(to: false)
        t.column("isManual", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.uniqueKey(["endpointId", "modelId"])
    }

    // 2. 迁移现有端点的模型数据
    // 每个端点的 modelName → endpoint_model（isDefault=true, isManual=true）

    // 3. 为 conversation 添加 modelName 列，回填自端点

    // 4. 从 api_endpoint 移除 modelName、maxContextTokens、apiMode 列
}
```

### v10_add_provider_dialect_to_endpoint_model

为 `endpoint_model` 添加 `providerDialect`，使 API 路由模式和供应商请求方言分离。历史记录默认 `openAICompatible`；`deepseek-v4-flash` / `deepseek-v4-pro` / `deepseek-v4-*` 自动标记为 `deepSeekV4`。当历史 DeepSeek V4 模型仍使用 4096 默认 context 时，迁移提升为 1,000,000，以符合 DeepSeek V4 1M 上下文能力。

```swift
migrator.registerMigration("v10_add_provider_dialect_to_endpoint_model") { db in
    try db.alter(table: Historical.endpointModelTable) { t in
        t.add(column: "providerDialect", .text)
            .notNull()
            .defaults(to: Historical.providerDialectOpenAICompatible)
    }
    try db.execute(sql: """
        UPDATE endpoint_model
        SET providerDialect = ?,
            maxContextTokens = CASE
                WHEN maxContextTokens = 4096 THEN 1000000
                ELSE maxContextTokens
            END
        WHERE lower(modelId) LIKE 'deepseek-v4-%'
        """, arguments: [Historical.providerDialectDeepSeekV4])
}
```

### v11_create_compression_checkpoints

新增 `conversation_compression_checkpoint` 表，保存持久化压缩 checkpoint。该迁移只追加新表和索引，不修改既有 `message` 表；原始消息仍完整保留。

```swift
migrator.registerMigration("v11_create_compression_checkpoints") { db in
    try db.create(table: Historical.compressionCheckpointTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("conversationId", .text).notNull()
            .references(Historical.conversationTable, onDelete: .cascade)
        t.column("parentCheckpointId", .text)
            .references(Historical.compressionCheckpointTable, onDelete: .setNull)
        t.column("sourceStartSortOrder", .integer).notNull()
        t.column("sourceEndSortOrder", .integer).notNull()
        t.column("sourceHash", .text).notNull()
        t.column("summary", .text).notNull()
        t.column("summaryTokenCount", .integer).notNull()
        t.column("endpointId", .text)
            .references(Historical.apiEndpointTable, onDelete: .setNull)
        t.column("modelName", .text).notNull()
        t.column("modelMaxContextTokens", .integer).notNull()
        t.column("effectiveCompactWindowTokens", .integer).notNull()
        t.column("autoCompactTokenLimit", .integer).notNull()
        t.column("createdAt", .datetime).notNull()
        t.uniqueKey(["conversationId", "sourceStartSortOrder", "sourceEndSortOrder", "sourceHash"])
    }
    try db.create(
        index: "idx_compression_checkpoint_conversationId",
        on: Historical.compressionCheckpointTable,
        columns: ["conversationId"]
    )
    try db.create(
        index: "idx_compression_checkpoint_sourceEnd",
        on: Historical.compressionCheckpointTable,
        columns: ["conversationId", "sourceEndSortOrder"]
    )
}
```

### v12_add_compression_mode_to_conversation

为 `conversation` 添加会话级压缩模式。历史会话默认使用 `standard`，即自动压缩阈值沿用 `maxContextTokens × 0.40`；用户可在对话设置里切换到 `highIntelligence`，由 `CompressionPolicy` 使用 `maxContextTokens × 0.25 × 0.90` 作为自动压缩阈值。

```swift
migrator.registerMigration("v12_add_compression_mode_to_conversation") { db in
    try db.alter(table: Historical.conversationTable) { t in
        t.add(column: "compressionMode", .text)
            .notNull()
            .defaults(to: Historical.compressionModeStandard)
    }
}
```

### v13_add_last_extracted_sort_order

为 `conversation` 添加 `lastExtractedSortOrder`，记录记忆提取已处理到的 message sortOrder。历史会话默认 `NULL`，首次提取按全量候选处理。

### v14_create_memory_entry_provenance

新增 `memory_entry_provenance` companion table，记录记忆提取 source range、source message ids、dedupe key、confidence、tags 和 prompt version。该表通过 `memoryEntryId` 级联到 `memory_entry`。

### v15_create_world_book_entry_embedding

新增世界书条目 sqlite-vec virtual table。该 migration 只建 schema，不执行 CoreML embedding 或 backfill。

```swift
migrator.registerMigration("v15_create_world_book_entry_embedding") { db in
    try db.execute(sql: """
        CREATE VIRTUAL TABLE \(Historical.worldBookEntryEmbeddingTable) USING vec0(
            entry_id TEXT PRIMARY KEY,
            embedding float[\(Historical.embeddingDimension)]
        )
    """)
}
```

### v16_create_world_book_entry_embedding_meta

新增世界书 embedding meta 表，用于 `indexed` / `needs_rebuild` / `failed` 状态审计和增量重建依据。Phase B indexer 以该表判断 fresh/missing/stale，并在成功或失败后更新对应状态。

```swift
migrator.registerMigration("v16_create_world_book_entry_embedding_meta") { db in
    try db.create(table: Historical.worldBookEntryEmbeddingMetaTable) { t in
        t.column("entryId", .text).notNull().primaryKey()
            .references(Historical.worldBookEntryTable, onDelete: .cascade)
        t.column("contentHash", .text).notNull()
        t.column("embeddingModel", .text).notNull()
        t.column("embeddingDimension", .integer).notNull()
        t.column("status", .text).notNull()
        t.column("embeddedAt", .datetime)
        t.column("lastAttemptAt", .datetime)
        t.column("lastError", .text)
        t.column("updatedAt", .datetime).notNull()
    }
}
```

实现证据：

- `OpenChat/Core/Database/Migrations.swift` 使用 `Historical.worldBookEntryEmbeddingTable`、`Historical.worldBookEntryEmbeddingMetaTable` 和 migration-local `Historical.embeddingDimension`。
- `OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift` 定义 meta Record。
- `OpenChat/Core/WorldBook/WorldBookVectorStore.swift` 提供 upsert/search/delete/deleteAll，search 限定 `worldBookId` 和 enabled entries。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 覆盖 v15/v16 schema、索引、cascade 和 migration forbidden references。
- `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift` 覆盖 upsert、worldBook 范围限定、disabled entry 过滤、delete 和维度错误无部分写入。

### v17_create_memory_entry_link

新增 `memory_entry_link` companion table，用于记录 reflect observation 与来源记忆之间的 based-on 关系。该迁移只追加新表和索引，不修改 v1-v16。

```swift
migrator.registerMigration("v17_create_memory_entry_link") { db in
    try db.create(table: Historical.memoryEntryLinkTable) { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("fromMemoryEntryId", .text).notNull()
            .references(Historical.memoryEntryTable, onDelete: .cascade)
        t.column("toMemoryEntryId", .text).notNull()
            .references(Historical.memoryEntryTable, onDelete: .cascade)
        t.column("relation", .text).notNull()
        t.column("createdAt", .datetime).notNull()
    }
}
```

实现证据：

- `OpenChat/Core/Database/Migrations.swift` 追加 `v17_create_memory_entry_link`。
- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift` 定义 target-backed `MemoryEntryLinkRecord`。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift` 提供 link save/fetch/validation。
- `OpenChat/Core/Memory/VectorStore.swift` 的 `insert(entry:embedding:links:)` 原子写 entry、embedding 和 links。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 覆盖 schema、索引和 from/to cascade。
- `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift` 覆盖 link fetch/dedupe/invalid relation。

### v18_create_stage_tables

新增 Stage 最小运行时持久层。该迁移追加三张 Stage 表，并为 `message` 追加 speaker metadata 列；不修改 v1-v17。

```swift
migrator.registerMigration("v18_create_stage_tables") { db in
    try db.create(table: Historical.stageTable) { ... }
    try db.create(table: Historical.stageParticipantTable) { ... }
    try db.create(table: Historical.stageInstructionTable) { ... }
    try db.alter(table: Historical.messageTable) { t in
        t.add(column: "stageId", .text)
        t.add(column: "speakerKind", .text)
        t.add(column: "speakerId", .text)
        t.add(column: "speakerName", .text)
    }
}
```

实现证据：

- `OpenChat/Core/Database/Migrations.swift` 追加 `v18_create_stage_tables`，使用 `Migrations.Historical` 本地常量。
- `OpenChat/Core/Database/Records/StageRecord.swift`、`StageParticipantRecord.swift`、`StageInstructionRecord.swift` 定义 GRDB Record。
- `OpenChat/Core/Database/Records/MessageRecord.swift` 追加 `stageId`、`speakerKind`、`speakerId`、`speakerName` 和 `speakerKindValue`。
- `OpenChat/Core/Database/DatabaseManager+Stage.swift` 提供 `fetchStageContext`、`createStage`、`setStageDirectorMode`、participant add/remove 和 `saveStageInstruction`。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 覆盖 stage tables、message speaker columns 和 conversation cascade。

---

## 数据库初始化

```swift
// DatabaseManager.swift
final class DatabaseManager {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }
}
```

数据库文件位置：`Application Support/OpenChat/database.sqlite`

---

## 设计决策

1. **所有 ID 使用 UUID 字符串**：避免自增 ID 在多设备同步时的冲突（预留 iCloud 同步能力）
2. **时间戳使用 ISO 8601 TEXT**：可读性好，GRDB 原生支持 Date ↔ TEXT 转换
3. **JSON 字段（exampleDialogs / keywords / tags / modelParameters）**：使用 TEXT 列存储 JSON 字符串，Swift 侧通过 Codable 解析。不使用独立关联表，减少表数量和查询复杂度
4. **avatar 使用 BLOB**：角色卡头像通常较小（< 500KB），直接内嵌数据库简化文件管理
5. **checkpoint 不替换原始消息**：上下文压缩摘要保存在 `conversation_compression_checkpoint`，原始 `message` 不删除、不改写，编辑或删除历史时删除受影响 checkpoint
6. **压缩模式属于会话状态**：`conversation.compressionMode` 决定 checkpoint 自动压缩阈值；checkpoint 记录生成时的阈值参数，模式切换后旧阈值 checkpoint 不再复用
7. **sortOrder 而非时间排序**：消息编辑/插入/重新生成时，时间戳不能保证顺序正确，使用显式 sortOrder 更可靠
