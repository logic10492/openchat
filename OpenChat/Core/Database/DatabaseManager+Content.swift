import Foundation
import GRDB

extension DatabaseManager {
    func fetchCharacterCards() async throws -> [CharacterCardRecord] {
        try await read { db in
            try CharacterCardRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchCharacterCard(id: String?) async throws -> CharacterCardRecord? {
        guard let id else { return nil }
        return try await read { db in
            try CharacterCardRecord.fetchOne(db, key: id)
        }
    }

    func saveCharacterCard(_ card: CharacterCardRecord) async throws {
        try await write { db in
            try card.save(db)
        }
    }

    func deleteCharacterCard(id: String) async throws {
        try await write { db in
            try db.execute(sql: """
                DELETE FROM memory_embedding
                WHERE entry_id IN (
                    SELECT id FROM memory_entry WHERE characterCardId = ?
                )
                """, arguments: [id])
            _ = try CharacterCardRecord.deleteOne(db, key: id)
        }
    }

    func fetchCharacterCards(worldBookId: String) async throws -> [CharacterCardRecord] {
        try await read { db in
            try CharacterCardRecord
                .filter(Column("worldBookId") == worldBookId)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchWorldBooks() async throws -> [WorldBookRecord] {
        try await read { db in
            try WorldBookRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchWorldBook(id: String?) async throws -> WorldBookRecord? {
        guard let id else { return nil }
        return try await read { db in
            try WorldBookRecord.fetchOne(db, key: id)
        }
    }

    func fetchWorldBookEntries(worldBookId: String?) async throws -> [WorldBookEntryRecord] {
        guard let worldBookId else { return [] }
        return try await read { db in
            try WorldBookEntryRecord
                .filter(Column("worldBookId") == worldBookId)
                .order(Column("priority").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func saveWorldBook(_ worldBook: WorldBookRecord) async throws {
        try await write { db in
            try worldBook.save(db)
        }
    }

    func saveWorldBookEntry(_ entry: WorldBookEntryRecord) async throws {
        try await write { db in
            try entry.save(db)
        }
    }

    func saveWorldBookEntries(_ entries: [WorldBookEntryRecord]) async throws {
        try await write { db in
            for entry in entries {
                try entry.save(db)
            }
        }
    }

    func deleteWorldBook(id: String) async throws {
        try await write { db in
            try self.deleteWorldBookEntryEmbeddings(worldBookId: id, in: db)
            _ = try WorldBookRecord.deleteOne(db, key: id)
        }
    }

    func deleteWorldBookEntry(id: String) async throws {
        try await write { db in
            try self.deleteWorldBookEntryEmbedding(entryId: id, in: db)
            _ = try WorldBookEntryRecord.deleteOne(db, key: id)
        }
    }

    func deleteWorldBookEntryEmbedding(entryId: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM world_book_entry_embedding WHERE entry_id = ?",
            arguments: [entryId]
        )
        _ = try WorldBookEntryEmbeddingMetaRecord.deleteOne(db, key: entryId)
    }

    func deleteWorldBookEntryEmbeddings(worldBookId: String, in db: Database) throws {
        try db.execute(sql: """
            DELETE FROM world_book_entry_embedding
            WHERE entry_id IN (
                SELECT id FROM world_book_entry WHERE worldBookId = ?
            )
            """, arguments: [worldBookId])
        try db.execute(sql: """
            DELETE FROM world_book_entry_embedding_meta
            WHERE entryId IN (
                SELECT id FROM world_book_entry WHERE worldBookId = ?
            )
            """, arguments: [worldBookId])
    }
}
