import Foundation
import GRDB
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
}
