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
}
