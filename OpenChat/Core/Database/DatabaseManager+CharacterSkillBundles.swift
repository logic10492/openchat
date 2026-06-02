import Foundation
import GRDB

extension DatabaseManager {
    func fetchCharacterSkillBundle(characterCardId: String?) async throws -> CharacterSkillBundleRecord? {
        guard let characterCardId else { return nil }
        return try await read { db in
            try CharacterSkillBundleRecord
                .filter(Column("characterCardId") == characterCardId)
                .fetchOne(db)
        }
    }

    func saveCharacterSkillBundle(_ bundle: CharacterSkillBundleRecord) async throws {
        try await write { db in
            try bundle.save(db)
        }
    }

    func saveCharacterCard(_ card: CharacterCardRecord, skillBundle: CharacterSkillBundleRecord) async throws {
        try await write { db in
            try card.save(db)
            try skillBundle.save(db)
        }
    }

    func deleteCharacterSkillBundle(characterCardId: String) async throws {
        try await write { db in
            _ = try CharacterSkillBundleRecord
                .filter(Column("characterCardId") == characterCardId)
                .deleteAll(db)
        }
    }
}
