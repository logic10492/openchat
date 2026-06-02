import Foundation

protocol CharacterSkillBundleMaterializing: Sendable {
    func materialize(characterCardId: String?) async throws -> RoleSkillPromptMaterial?
}

struct CharacterSkillBundleMaterializer: CharacterSkillBundleMaterializing {
    let databaseManager: DatabaseManager
    let store: CharacterSkillBundleStore

    func materialize(characterCardId: String?) async throws -> RoleSkillPromptMaterial? {
        guard let record = try await databaseManager.fetchCharacterSkillBundle(characterCardId: characterCardId) else {
            return nil
        }
        let markdown = try store.readSkillMarkdown(for: record)
        return RoleSkillPromptMaterial(
            name: record.skillName,
            source: "character_skill_bundle:\(record.id):\(record.skillMarkdownSha256)",
            skillMarkdown: markdown
        )
    }
}
