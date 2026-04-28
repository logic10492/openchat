import Foundation
import GRDB
import SqliteVec
import Testing

@testable import OpenChat

@Suite("Database migrations")
struct MigrationTests {
    @Test func test_migrations_do_not_reference_runtime_record_or_enum_symbols() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migrationsURL = projectRoot
            .appendingPathComponent("OpenChat")
            .appendingPathComponent("Core")
            .appendingPathComponent("Database")
            .appendingPathComponent("Migrations.swift")
        let source = try String(contentsOf: migrationsURL, encoding: .utf8)
        let forbiddenReferences = [
            ".databaseTableName",
            "APIMode.",
            "WorldBookEntryPosition.",
            "ContextStrategy."
        ]
        let violations = forbiddenReferences.filter { source.contains($0) }

        #expect(
            violations.isEmpty,
            "Migrations must use migration-local historical constants, not runtime symbols: \(violations.joined(separator: ", "))"
        )
    }

    @Test func test_v1_creates_expected_tables_and_indexes() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }

        #expect(tableNames.contains("api_endpoint"))
        #expect(tableNames.contains("character_card"))
        #expect(tableNames.contains("world_book"))
        #expect(tableNames.contains("world_book_entry"))
        #expect(tableNames.contains("conversation"))
        #expect(tableNames.contains("message"))
    }

    @Test func test_foreign_key_cascade_removes_world_book_entries() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook()
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id)

        try await manager.write { db in
            try worldBook.insert(db)
            try entry.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM world_book WHERE id = ?", arguments: [worldBook.id])
        }

        let count = try await manager.read { db in
            try WorldBookEntryRecord.fetchCount(db)
        }

        #expect(count == 0)
    }

    @Test func test_v2_adds_worldBookId_to_character_card() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "character_card").map(\.name)
        }
        #expect(columns.contains("worldBookId"))
    }

    @Test func test_v2_character_card_worldBookId_set_null_on_world_book_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook()
        let now = Date()
        var card = CharacterCardRecord(
            id: UUID().uuidString,
            name: "Test",
            createdAt: now,
            updatedAt: now
        )
        card.worldBookId = worldBook.id
        let cardSnapshot = card

        try await manager.write { db in
            try worldBook.insert(db)
            try cardSnapshot.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM world_book WHERE id = ?", arguments: [worldBook.id])
        }

        let updated = try await manager.read { db in
            try CharacterCardRecord.fetchOne(db, key: cardSnapshot.id)
        }
        #expect(updated?.worldBookId == nil)
    }

    @Test func test_v3_removes_worldBookId_from_conversation() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(!columns.contains("worldBookId"))
    }

    @Test func test_v4_creates_memory_entry_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        #expect(tableNames.contains("memory_entry"))
    }

    @Test func test_v4_memory_entry_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "memory_entry").map(\.name)
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("characterCardId"))
        #expect(columns.contains("sourceConversationId"))
        #expect(columns.contains("content"))
        #expect(columns.contains("memoryType"))
        #expect(columns.contains("importance"))
        #expect(columns.contains("createdAt"))
        #expect(columns.contains("updatedAt"))
    }

    @Test func test_v4_memory_entry_cascade_on_character_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)

        try await manager.write { db in
            try card.insert(db)
            try memory.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM character_card WHERE id = ?", arguments: [card.id])
        }

        let count = try await manager.read { db in
            try MemoryEntryRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v8 endpoint_model decoupling

    @Test func test_v8_creates_endpoint_model_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        #expect(tableNames.contains("endpoint_model"))
    }

    @Test func test_v8_endpoint_model_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "endpoint_model").map(\.name)
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("endpointId"))
        #expect(columns.contains("modelId"))
        #expect(columns.contains("maxContextTokens"))
        #expect(columns.contains("apiMode"))
        #expect(columns.contains("isDefault"))
        #expect(columns.contains("isManual"))
        #expect(columns.contains("createdAt"))
    }

    @Test func test_v8_conversation_has_modelName_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(columns.contains("modelName"))
    }

    @Test func test_v8_api_endpoint_no_longer_has_model_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "api_endpoint").map(\.name)
        }
        #expect(!columns.contains("modelName"))
        #expect(!columns.contains("maxContextTokens"))
        #expect(!columns.contains("apiMode"))
    }

    @Test func test_v8_endpoint_model_cascade_on_endpoint_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "ep1",
            name: "Test",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "m1",
            endpointId: "ep1",
            modelId: "gpt-4o",
            maxContextTokens: 4096,
            apiMode: "chatCompletions",
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: false,
            createdAt: now
        )

        try await manager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM api_endpoint WHERE id = 'ep1'")
        }

        let count = try await manager.read { db in
            try EndpointModelRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v9

    @Test func test_v9_conversation_has_isTitleGenerated_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(columns.contains("isTitleGenerated"))
    }

    @Test func test_v9_isTitleGenerated_defaults_to_false() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation()
        try await manager.write { db in
            try conversation.insert(db)
        }

        let fetched = try await manager.read { db in
            try ConversationRecord.fetchOne(db, id: conversation.id)
        }

        #expect(fetched?.isTitleGenerated == false)
    }

    // MARK: - v10 provider dialect

    @Test func test_v10_endpoint_model_has_providerDialect_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "endpoint_model").map(\.name)
        }

        #expect(columns.contains("providerDialect"))
    }

    @Test func test_v10_providerDialect_defaults_to_openAICompatible() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "ep-provider-default",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        try await manager.saveEndpoint(endpoint)
        try await manager.ensureDefaultModel(endpointId: endpoint.id)

        let model = try await manager.fetchDefaultModel(endpointId: endpoint.id)
        #expect(model?.providerDialect == "openAICompatible")
    }

    @Test func test_v10_backfills_existing_deepseek_v4_models() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            if let connection = db.sqliteConnection {
                registerSqliteVec(connection)
            }
        }
        let dbQueue = try DatabaseQueue(configuration: configuration)
        var migrator = Migrations.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v9_add_is_title_generated")

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO api_endpoint (id, name, baseURL, apiKey, isDefault, createdAt, updatedAt)
                VALUES ('ep-deepseek', 'DeepSeek', 'https://api.deepseek.com', NULL, 1, ?, ?)
                """, arguments: [Date(), Date()])
            try db.execute(sql: """
                INSERT INTO endpoint_model (id, endpointId, modelId, maxContextTokens, apiMode, isDefault, isManual, createdAt)
                VALUES ('model-deepseek-pro', 'ep-deepseek', 'deepseek-v4-pro', 4096, 'chatCompletions', 1, 1, ?)
                """, arguments: [Date()])
        }

        try migrator.migrate(dbQueue)

        let row = try dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT providerDialect, maxContextTokens
                FROM endpoint_model
                WHERE id = 'model-deepseek-pro'
                """)
        }

        #expect(row?["providerDialect"] as String? == "deepSeekV4")
        #expect(row?["maxContextTokens"] as Int? == 1_000_000)
    }
}
