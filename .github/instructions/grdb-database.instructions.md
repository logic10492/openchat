---
description: "Use when working with GRDB database layer, records, migrations, or database queries in the OpenChat project. Covers Record types, migration rules, query patterns, and thread safety."
applyTo: "**/Database/**/*.swift"
---
# GRDB 数据库层规范

## Record 类型

- 所有 Record 实现 `Codable, FetchableRecord, PersistableRecord`
- Record 为 `struct`，不使用 `class`
- 表名通过 `static let databaseTableName` 显式指定（snake_case）
- 属性名使用 Swift camelCase，GRDB 自动映射到数据库列名

```swift
struct CharacterCardRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "character_card"
    var id: String
    var name: String
    var createdAt: Date
    ...
}
```

## 主键

- 所有表使用 `id TEXT PRIMARY KEY`（UUID 字符串）
- 生成方式: `UUID().uuidString`
- 不使用自增整数 ID（预留多设备同步能力）

## 关联

- 使用 GRDB 的 `belongsTo` / `hasMany` 声明关系
- 外键约束在 migration 中通过 `.references()` 定义
- 级联规则:
  - `conversation.characterCardId` → `onDelete: .setNull`
  - `conversation.worldBookId` → `onDelete: .setNull`
  - `conversation.apiEndpointId` → `onDelete: .setNull`
  - `message.conversationId` → `onDelete: .cascade`
  - `world_book_entry.worldBookId` → `onDelete: .cascade`

## Migration

- 使用 `DatabaseMigrator` 管理，所有 migration 注册在 `Migrations.swift`
- 命名格式: `v{N}_{description}`，如 `v1_initial`, `v2_add_avatar_column`
- **只追加，不修改已有 migration**
- 新增列使用 `ALTER TABLE ... ADD COLUMN`，不重建表
- migration 中不引用 Record 类型（防止 Record 修改影响旧 migration）
- migration 中使用 GRDB DDL API 或原始 SQL

```swift
// ✅ 正确
migrator.registerMigration("v2_add_pinned") { db in
    try db.alter(table: "conversation") { t in
        t.add(column: "isPinned", .boolean).notNull().defaults(to: false)
    }
}

// ❌ 错误：在 migration 中引用 Record 类型
migrator.registerMigration("v2") { db in
    try ConversationRecord.createTable(db)  // Record 结构变化会破坏此 migration
}
```

## 查询模式

- 读操作使用 `dbQueue.read { db in ... }`
- 写操作使用 `dbQueue.write { db in ... }`
- 批量写操作放在同一个 `write` 块中（事务）
- 列表查询添加 `ORDER BY` 和合理的 `LIMIT`
- 使用 GRDB 的 query interface 而非裸 SQL

```swift
// ✅ 读取
let messages = try await db.dbQueue.read { db in
    try MessageRecord
        .filter(Column("conversationId") == conversationId)
        .order(Column("sortOrder").asc)
        .fetchAll(db)
}

// ✅ 写入
try await db.dbQueue.write { db in
    try record.save(db)
}
```

## 索引

- 外键列创建索引
- 频繁排序/过滤的列创建索引
- 索引在 migration 中与建表一起定义
- 索引命名: `idx_{table}_{column}`

## 线程安全

- `DatabaseQueue` 作为单例在 `DatabaseManager` 中持有
- 所有数据库访问通过 `DatabaseManager` 提供的方法
- 不在 View 或 ViewModel 中直接持有 `DatabaseQueue`
- 数据库操作都是 `async`，不阻塞主线程

## JSON 字段

以下字段以 JSON TEXT 形式存储：
- `character_card.exampleDialogs`: `[{"role":"user","content":"..."},...]`
- `character_card.tags`: `["fantasy","sci-fi"]`
- `world_book_entry.keywords`: `["精灵","elf"]`
- `conversation.modelParameters`: `{"temperature":0.8,...}`

Swift 侧通过 `JSONEncoder`/`JSONDecoder` 转换，可在 Record 上添加计算属性或辅助方法。

## DatabaseManager

```swift
final class DatabaseManager: Sendable {
    let dbQueue: DatabaseQueue

    init(path: String) throws   // 初始化 + 执行 migration
}
```

- 数据库文件位置: `Application Support/OpenChat/database.sqlite`
- App 启动时由 `DependencyContainer` 创建并持有
- 通过 init 注入到需要的 ViewModel 和 Core 服务
