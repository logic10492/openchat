import Foundation
import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try createTables(db)
            try createIndexes(db)
        }
        return migrator
    }

    private static func createTables(_ db: Database) throws {
        try db.create(table: APIEndpointRecord.databaseTableName) { t in
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

        try db.create(table: CharacterCardRecord.databaseTableName) { t in
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

        try db.create(table: WorldBookRecord.databaseTableName) { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("isEnabled", .boolean).notNull().defaults(to: true)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: WorldBookEntryRecord.databaseTableName) { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("worldBookId", .text).notNull().references(WorldBookRecord.databaseTableName, onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("content", .text).notNull()
            t.column("keywords", .text).notNull()
            t.column("priority", .integer).notNull().defaults(to: 50)
            t.column("isEnabled", .boolean).notNull().defaults(to: true)
            t.column("position", .text).notNull().defaults(to: WorldBookEntryPosition.beforeHistory.rawValue)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: ConversationRecord.databaseTableName) { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("title", .text).notNull()
            t.column("characterCardId", .text).references(CharacterCardRecord.databaseTableName, onDelete: .setNull)
            t.column("worldBookId", .text).references(WorldBookRecord.databaseTableName, onDelete: .setNull)
            t.column("apiEndpointId", .text).references(APIEndpointRecord.databaseTableName, onDelete: .setNull)
            t.column("contextStrategy", .text).notNull().defaults(to: ContextStrategy.truncation.rawValue)
            t.column("customScenario", .text)
            t.column("modelParameters", .text)
            t.column("isPinned", .boolean).notNull().defaults(to: false)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: MessageRecord.databaseTableName) { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("conversationId", .text).notNull().references(ConversationRecord.databaseTableName, onDelete: .cascade)
            t.column("role", .text).notNull()
            t.column("content", .text).notNull()
            t.column("tokenCount", .integer)
            t.column("isCompressed", .boolean).notNull().defaults(to: false)
            t.column("originalContent", .text)
            t.column("sortOrder", .integer).notNull()
            t.column("createdAt", .datetime).notNull()
        }
    }

    private static func createIndexes(_ db: Database) throws {
        try db.create(index: "idx_message_conversationId", on: MessageRecord.databaseTableName, columns: ["conversationId"])
        try db.create(index: "idx_message_sortOrder", on: MessageRecord.databaseTableName, columns: ["conversationId", "sortOrder"])
        try db.create(index: "idx_world_book_entry_worldBookId", on: WorldBookEntryRecord.databaseTableName, columns: ["worldBookId"])
        try db.create(index: "idx_conversation_characterCardId", on: ConversationRecord.databaseTableName, columns: ["characterCardId"])
        try db.create(index: "idx_conversation_updatedAt", on: ConversationRecord.databaseTableName, columns: ["updatedAt"])
    }
}
