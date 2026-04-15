import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("Database migrations")
struct MigrationTests {
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
}
