import Foundation
import GRDB

enum Migrations {
    private enum Historical {
        static let apiEndpointTable = "api_endpoint"
        static let characterCardTable = "character_card"
        static let worldBookTable = "world_book"
        static let worldBookEntryTable = "world_book_entry"
        static let conversationTable = "conversation"
        static let messageTable = "message"
        static let memoryEntryTable = "memory_entry"
        static let memoryEmbeddingTable = "memory_embedding"
        static let endpointModelTable = "endpoint_model"
        static let compressionCheckpointTable = "conversation_compression_checkpoint"

        static let apiModeChatCompletions = "chatCompletions"
        static let providerDialectOpenAICompatible = "openAICompatible"
        static let providerDialectDeepSeekV4 = "deepSeekV4"
        static let worldBookEntryBeforeHistory = "before_history"
        static let contextStrategyTruncation = "truncation"
    }

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try createTables(db)
            try createIndexes(db)
        }
        migrator.registerMigration("v2_world_book_character_card") { db in
            try db.alter(table: Historical.characterCardTable) { t in
                t.add(column: "worldBookId", .text)
                    .references(Historical.worldBookTable, onDelete: .setNull)
            }
            try db.create(
                index: "idx_character_card_worldBookId",
                on: Historical.characterCardTable,
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

            try db.alter(table: Historical.conversationTable) { t in
                t.drop(column: "worldBookId")
            }
        }
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

            try db.create(
                index: "idx_memory_entry_characterCardId",
                on: Historical.memoryEntryTable,
                columns: ["characterCardId"]
            )
            try db.create(
                index: "idx_memory_entry_sourceConversationId",
                on: Historical.memoryEntryTable,
                columns: ["sourceConversationId"]
            )

            try db.execute(sql: """
                CREATE VIRTUAL TABLE \(Historical.memoryEmbeddingTable) USING vec0(
                    entry_id TEXT PRIMARY KEY,
                    embedding float[384]
                )
                """)
        }
        migrator.registerMigration("v5_addApiMode") { db in
            try db.alter(table: Historical.apiEndpointTable) { t in
                t.add(column: "apiMode", .text).notNull().defaults(to: Historical.apiModeChatCompletions)
            }
        }
        migrator.registerMigration("v6_add_reasoning_content") { db in
            try db.alter(table: Historical.messageTable) { t in
                t.add(column: "reasoningContent", .text)
            }
        }
        migrator.registerMigration("v7_add_slow_plot_mode") { db in
            try db.alter(table: Historical.conversationTable) { t in
                t.add(column: "slowPlotMode", .boolean).notNull().defaults(to: true)
            }
        }
        migrator.registerMigration("v8_endpoint_model_decoupling") { db in
            // 1. Create endpoint_model table
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
            try db.create(
                index: "idx_endpoint_model_endpointId",
                on: Historical.endpointModelTable,
                columns: ["endpointId"]
            )

            // 2. Migrate existing endpoint model data into endpoint_model table
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, modelName, maxContextTokens, apiMode FROM api_endpoint
                """)
            let now = Date()
            for row in rows {
                let endpointId: String = row["id"]
                let modelName: String = row["modelName"]
                let maxCtx: Int = row["maxContextTokens"]
                let apiMode: String = row["apiMode"]
                try db.execute(sql: """
                    INSERT INTO endpoint_model (id, endpointId, modelId, maxContextTokens, apiMode, isDefault, isManual, createdAt)
                    VALUES (?, ?, ?, ?, ?, 1, 1, ?)
                    """, arguments: [UUID().uuidString, endpointId, modelName, maxCtx, apiMode, now])
            }

            // 3. Add modelName column to conversation and back-fill from endpoint
            try db.alter(table: Historical.conversationTable) { t in
                t.add(column: "modelName", .text)
            }
            try db.execute(sql: """
                UPDATE conversation SET modelName = (
                    SELECT modelName FROM api_endpoint WHERE api_endpoint.id = conversation.apiEndpointId
                ) WHERE apiEndpointId IS NOT NULL
                """)

            // 4. Drop migrated columns from api_endpoint (SQLite 3.35+, iOS 16+)
            try db.alter(table: Historical.apiEndpointTable) { t in
                t.drop(column: "modelName")
                t.drop(column: "maxContextTokens")
                t.drop(column: "apiMode")
            }
        }
        migrator.registerMigration("v9_add_is_title_generated") { db in
            try db.alter(table: Historical.conversationTable) { t in
                t.add(column: "isTitleGenerated", .boolean).notNull().defaults(to: false)
            }
        }
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
        return migrator
    }

    private static func createTables(_ db: Database) throws {
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
            t.column("worldBookId", .text).notNull().references(Historical.worldBookTable, onDelete: .cascade)
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
            t.column("characterCardId", .text).references(Historical.characterCardTable, onDelete: .setNull)
            t.column("worldBookId", .text).references(Historical.worldBookTable, onDelete: .setNull)
            t.column("apiEndpointId", .text).references(Historical.apiEndpointTable, onDelete: .setNull)
            t.column("contextStrategy", .text).notNull().defaults(to: Historical.contextStrategyTruncation)
            t.column("customScenario", .text)
            t.column("modelParameters", .text)
            t.column("isPinned", .boolean).notNull().defaults(to: false)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        try db.create(table: Historical.messageTable) { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("conversationId", .text).notNull().references(Historical.conversationTable, onDelete: .cascade)
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
        try db.create(index: "idx_message_conversationId", on: Historical.messageTable, columns: ["conversationId"])
        try db.create(index: "idx_message_sortOrder", on: Historical.messageTable, columns: ["conversationId", "sortOrder"])
        try db.create(index: "idx_world_book_entry_worldBookId", on: Historical.worldBookEntryTable, columns: ["worldBookId"])
        try db.create(index: "idx_conversation_characterCardId", on: Historical.conversationTable, columns: ["characterCardId"])
        try db.create(index: "idx_conversation_updatedAt", on: Historical.conversationTable, columns: ["updatedAt"])
    }
}
