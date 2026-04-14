import Foundation
import GRDB

struct CharacterCardRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "character_card"

    var id: String
    var name: String
    var avatar: Data?
    var personality: String?
    var appearance: String?
    var physique: String?
    var speechStyle: String?
    var backstory: String?
    var systemPrompt: String?
    var scenario: String?
    var exampleDialogs: String?
    var creatorNotes: String?
    var tags: String?
    var createdAt: Date
    var updatedAt: Date

    func exampleDialogMessages() throws -> [ChatMessage] {
        guard let exampleDialogs, !exampleDialogs.isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([ChatMessage].self, from: Data(exampleDialogs.utf8))
        } catch {
            throw PromptError.invalidJSON(field: "character_card.exampleDialogs", underlying: error)
        }
    }

    func tagValues() throws -> [String] {
        guard let tags, !tags.isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([String].self, from: Data(tags.utf8))
        } catch {
            throw PromptError.invalidJSON(field: "character_card.tags", underlying: error)
        }
    }

    var decodedExampleDialogs: [ChatMessage] {
        (try? exampleDialogMessages()) ?? []
    }

    var decodedTags: [String] {
        (try? tagValues()) ?? []
    }
}
