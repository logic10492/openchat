import Foundation
import GRDB

enum WorldBookEntryPosition: String, Codable, CaseIterable, Sendable {
    case afterSystem = "after_system"
    case beforeHistory = "before_history"

    var displayName: String {
        switch self {
        case .afterSystem:
            return String(localized: "After system")
        case .beforeHistory:
            return String(localized: "Before history")
        }
    }
}

struct WorldBookEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "world_book_entry"

    var id: String
    var worldBookId: String
    var title: String
    var content: String
    var keywords: String
    var priority: Int
    var isEnabled: Bool
    var position: String
    var createdAt: Date
    var updatedAt: Date

    static let worldBook = belongsTo(WorldBookRecord.self)

    func keywordValues() throws -> [String] {
        guard !keywords.isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([String].self, from: Data(keywords.utf8))
        } catch {
            throw PromptError.invalidJSON(field: "world_book_entry.keywords", underlying: error)
        }
    }

    var positionValue: WorldBookEntryPosition? {
        WorldBookEntryPosition(rawValue: position)
    }

    var decodedKeywords: [String] {
        (try? keywordValues()) ?? []
    }
}
