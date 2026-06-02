import Foundation
import GRDB

struct CharacterSkillBundleRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "character_skill_bundle"

    var id: String
    var characterCardId: String
    var sourceKind: String
    var sourceFileName: String?
    var sourceArchiveSha256: String
    var bundleRelativePath: String
    var skillMarkdownRelativePath: String
    var skillMarkdownSha256: String
    var skillName: String
    var skillDescription: String
    var skillShortDescription: String?
    var frontmatterJSON: String
    var agentsOpenAIYamlJSON: String?
    var fileManifestJSON: String
    var materializationMode: String
    var createdAt: Date
    var updatedAt: Date
}
