import Foundation
import GRDB

struct StageRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage"

    var id: String
    var conversationId: String
    var title: String?
    var directorMode: String
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    static let conversation = belongsTo(ConversationRecord.self)
    static let participants = hasMany(StageParticipantRecord.self)
    static let instructions = hasMany(StageInstructionRecord.self)

    var directorModeValue: DirectorMode {
        DirectorMode(rawValue: directorMode) ?? .silent
    }
}
