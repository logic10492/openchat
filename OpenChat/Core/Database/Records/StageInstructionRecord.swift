import Foundation
import GRDB

struct StageInstructionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "stage_instruction"

    var id: String
    var stageId: String
    var source: String
    var content: String
    var visibility: String
    var createdAt: Date

    static let stage = belongsTo(StageRecord.self)

    var sourceValue: StageInstructionSource {
        StageInstructionSource(rawValue: source) ?? .user
    }

    var visibilityValue: StageInstructionVisibility {
        StageInstructionVisibility(rawValue: visibility) ?? .hiddenFromCharacters
    }

    var stageInstruction: StageInstruction? {
        try? StageInstruction(
            id: id,
            source: sourceValue,
            content: content,
            visibility: visibilityValue,
            createdAt: createdAt
        )
    }
}
