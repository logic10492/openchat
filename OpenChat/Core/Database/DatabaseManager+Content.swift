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
            _ = try CharacterCardRecord.deleteOne(db, key: id)
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

    func deleteWorldBook(id: String) async throws {
        try await write { db in
            _ = try WorldBookRecord.deleteOne(db, key: id)
        }
    }

    func deleteWorldBookEntry(id: String) async throws {
        try await write { db in
            _ = try WorldBookEntryRecord.deleteOne(db, key: id)
        }
    }
}
