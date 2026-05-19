import Foundation
import GRDB

struct StageParticipantRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage_participant"

    var id: String
    var stageId: String
    var characterCardId: String
    var displayName: String
    var visibility: String
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    static let stage = belongsTo(StageRecord.self)
    static let characterCard = belongsTo(CharacterCardRecord.self)

    var visibilityValue: StageParticipantVisibility {
        StageParticipantVisibility(rawValue: visibility) ?? .present
    }
}
