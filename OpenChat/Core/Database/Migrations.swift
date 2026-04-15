import Foundation
import GRDB

enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try createTables(db)
            try createIndexes(db)
        }
        migrator.registerMigration("v2_world_book_character_card") { db in
            try db.alter(table: "character_card") { t in
                t.add(column: "worldBookId", .text)
                    .references("world_book", onDelete: .setNull)
            }
            try db.create(
                index: "idx_character_card_worldBookId",
                on: "character_card",
                columns: ["worldBookId"]
            )
        }
        migrator.registerMigration("v3_remove_world_book_from_conversation") { db in
            // Migrate worldBookId from conversation to character_card
            try db.execute(sql: """
                UPDATE character_card SET worldBookId = (
                    SELECT c.worldBookId FROM conversation c
                    WHERE c.characterCardId = character_card.id
                    AND c.worldBookId IS NOT NULL
                    LIMIT 1
                )
                WHERE worldBookId IS NULL
                """)

            try db.alter(table: "conversation") { t in
                t.drop(column: "worldBookId")
            }
        }
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

            try db.create(
                index: "idx_memory_entry_characterCardId",
                on: "memory_entry",
                columns: ["characterCardId"]
            )
            try db.create(
                index: "idx_memory_entry_sourceConversationId",
                on: "memory_entry",
                columns: ["sourceConversationId"]
            )

            try db.execute(sql: """
                CREATE VIRTUAL TABLE memory_embedding USING vec0(
                    entry_id TEXT PRIMARY KEY,
                    embedding float[384]
                )
                """)
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
