import Foundation
import GRDB

struct ConversationRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "conversation"

    var id: String
    var title: String
    var characterCardId: String?
    var apiEndpointId: String?
    var contextStrategy: String
    var customScenario: String?
    var modelParameters: String?
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    static let characterCard = belongsTo(CharacterCardRecord.self)
    static let apiEndpoint = belongsTo(APIEndpointRecord.self)
    static let messages = hasMany(MessageRecord.self)

    var contextStrategyValue: ContextStrategy {
        ContextStrategy(rawValue: contextStrategy) ?? .truncation
    }

    func modelParametersValue() throws -> ModelParameters? {
        guard let modelParameters, !modelParameters.isEmpty else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ModelParameters.self, from: Data(modelParameters.utf8))
        } catch {
            throw PromptError.invalidJSON(field: "conversation.modelParameters", underlying: error)
        }
    }

    var decodedModelParameters: ModelParameters? {
        try? modelParametersValue()
    }
}
