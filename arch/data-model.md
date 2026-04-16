# 数据模型定义

## 概述

持久层使用 **GRDB.swift** 操作 SQLite。所有表定义为 GRDB `Record` 子类（或实现 `FetchableRecord + PersistableRecord`）。本文档定义所有表结构、字段、约束、关系及迁移策略。

---

## 表结构

### 1. api_endpoint — API 端点配置

存储用户添加的 OpenAI 兼容 API 端点。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK, NOT NULL | UUID 字符串 |
| name | TEXT | NOT NULL | 显示名称，如 "本地 Llama" |
| baseURL | TEXT | NOT NULL | 接口基础地址，如 `http://localhost:8080/v1` |
| apiKey | TEXT | | API 密钥（可选，本地模型可为空） |
| modelName | TEXT | NOT NULL | 默认模型标识符，如 `gpt-3.5-turbo` |
| maxContextTokens | INTEGER | NOT NULL, DEFAULT 4096 | 该端点支持的最大上下文 token 数 |
| isDefault | INTEGER | NOT NULL, DEFAULT 0 | 是否为默认端点（布尔值） |
| apiMode | TEXT | NOT NULL, DEFAULT 'chatCompletions' | API 模式：`chatCompletions` / `responses` |
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
    var modelName: String
    var maxContextTokens: Int
    var isDefault: Bool
    var apiMode: String          // "chatCompletions" | "responses"
    var createdAt: Date
    var updatedAt: Date
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
| position | TEXT | NOT NULL, DEFAULT 'before_history' | 注入位置：`before_history` / `after_system` |
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
    var position: String             // "before_history" | "after_system"
    var createdAt: Date
    var updatedAt: Date

    static let worldBook = belongsTo(WorldBookRecord.self)
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
| contextStrategy | TEXT | NOT NULL, DEFAULT 'truncation' | 上下文策略：`truncation` / `compression` |
| customScenario | TEXT | | 会话专属场景覆盖（优先于角色卡场景） |
| modelParameters | TEXT | | 模型参数覆盖（JSON: `{"temperature":0.8,...}`） |
| isPinned | INTEGER | NOT NULL, DEFAULT 0 | 是否置顶 |
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
    var contextStrategy: String      // "truncation" | "compression"
    var customScenario: String?
    var modelParameters: String?     // JSON
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    static let characterCard = belongsTo(CharacterCardRecord.self)
    static let apiEndpoint = belongsTo(APIEndpointRecord.self)
    static let messages = hasMany(MessageRecord.self)
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

**外键**：`conversationId` → `conversation(id)` ON DELETE CASCADE

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

## 实体关系图（文字 ER）

```
api_endpoint 1 ──── 0..* conversation
character_card 1 ──── 0..* conversation
world_book 1 ──── 0..* character_card
world_book 1 ──── 0..* world_book_entry
character_card 1 ──── 0..* memory_entry
conversation 1 ──── 0..* memory_entry
conversation 1 ──── 0..* message
```

关系说明：
- 一个 `conversation` 可选绑定一个 `character_card`、一个 `api_endpoint`
- 一个 `character_card` 可选归属于一个 `world_book`（世界书通过角色卡间接关联到对话）
- 一个 `world_book` 包含多个 `world_book_entry`
- 一个 `character_card` 关联多条 `memory_entry`（跨对话记忆）
- 一个 `conversation` 包含多条 `message`
- 一个 `conversation` 可关联多条 `memory_entry`（记忆来源）
- 删除 `conversation` 时级联删除其所有 `message`
- 删除 `world_book` 时级联删除其所有 `world_book_entry`
- 删除 `character_card` 时级联删除其所有 `memory_entry`
- 删除 `character_card` / `api_endpoint` 时，关联 `conversation` 的外键置 NULL
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

    try db.create(table: "api_endpoint") { t in
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

    try db.create(table: "character_card") { t in
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

    try db.create(table: "world_book") { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("name", .text).notNull()
        t.column("description", .text)
        t.column("isEnabled", .boolean).notNull().defaults(to: true)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: "world_book_entry") { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("worldBookId", .text).notNull()
            .references("world_book", onDelete: .cascade)
        t.column("title", .text).notNull()
        t.column("content", .text).notNull()
        t.column("keywords", .text).notNull()
        t.column("priority", .integer).notNull().defaults(to: 50)
        t.column("isEnabled", .boolean).notNull().defaults(to: true)
        t.column("position", .text).notNull().defaults(to: "before_history")
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: "conversation") { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("title", .text).notNull()
        t.column("characterCardId", .text)
            .references("character_card", onDelete: .setNull)
        t.column("apiEndpointId", .text)
            .references("api_endpoint", onDelete: .setNull)
        t.column("contextStrategy", .text).notNull().defaults(to: "truncation")
        t.column("customScenario", .text)
        t.column("modelParameters", .text)
        t.column("isPinned", .boolean).notNull().defaults(to: false)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(table: "message") { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("conversationId", .text).notNull()
            .references("conversation", onDelete: .cascade)
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
try db.create(index: "idx_message_conversationId", on: "message", columns: ["conversationId"])
try db.create(index: "idx_message_sortOrder", on: "message", columns: ["conversationId", "sortOrder"])
try db.create(index: "idx_world_book_entry_worldBookId", on: "world_book_entry", columns: ["worldBookId"])
try db.create(index: "idx_conversation_characterCardId", on: "conversation", columns: ["characterCardId"])
try db.create(index: "idx_conversation_updatedAt", on: "conversation", columns: ["updatedAt"])
```

### v2_world_book_character_card

角色卡归属世界书：为 `character_card` 表添加 `worldBookId` 外键。

```swift
migrator.registerMigration("v2_world_book_character_card") { db in
    try db.alter(table: "character_card") { t in
        t.add(column: "worldBookId", .text)
            .references("world_book", onDelete: .setNull)
    }
    try db.create(index: "idx_character_card_worldBookId",
                  on: "character_card", columns: ["worldBookId"])
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
    try db.alter(table: "conversation") { t in
        t.drop(column: "worldBookId")
    }
}
```

### v4_create_memory_tables

创建记忆条目表和 sqlite-vec 向量嵌入虚拟表。

```swift
migrator.registerMigration("v4_create_memory_tables") { db in
    try db.create(table: "memory_entry") { t in
        t.column("id", .text).notNull().primaryKey()
        t.column("characterCardId", .text).notNull()
            .references("character_card", onDelete: .cascade)
        t.column("sourceConversationId", .text)
            .references("conversation", onDelete: .setNull)
        t.column("content", .text).notNull()
        t.column("memoryType", .text).notNull()
        t.column("importance", .integer).notNull().defaults(to: 50)
        t.column("createdAt", .datetime).notNull()
        t.column("updatedAt", .datetime).notNull()
    }

    try db.create(index: "idx_memory_entry_characterCardId",
                  on: "memory_entry", columns: ["characterCardId"])
    try db.create(index: "idx_memory_entry_sourceConversationId",
                  on: "memory_entry", columns: ["sourceConversationId"])

    // sqlite-vec 虚拟表：存储 384 维嵌入向量
    try db.execute(sql: """
        CREATE VIRTUAL TABLE memory_embedding USING vec0(
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

### v5_addApiMode

为 `api_endpoint` 表添加 `apiMode` 列，支持 Chat Completions 和 Responses API 两种模式切换。

```swift
migrator.registerMigration("v5_addApiMode") { db in
    try db.alter(table: "api_endpoint") { t in
        t.add(column: "apiMode", .text).notNull().defaults(to: APIMode.chatCompletions.rawValue)
    }
}
```

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
5. **消息保留 originalContent**：压缩消息时保留原文，允许用户回溯查看
6. **sortOrder 而非时间排序**：消息编辑/插入/重新生成时，时间戳不能保证顺序正确，使用显式 sortOrder 更可靠
