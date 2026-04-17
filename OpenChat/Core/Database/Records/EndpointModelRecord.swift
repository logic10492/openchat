import Foundation
import GRDB

struct EndpointModelRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "endpoint_model"

    var id: String
    var endpointId: String
    var modelId: String
    var maxContextTokens: Int
    var apiMode: String
    var isDefault: Bool
    var isManual: Bool
    var createdAt: Date

    var apiModeValue: APIMode {
        get { APIMode(rawValue: apiMode) ?? .chatCompletions }
        set { apiMode = newValue.rawValue }
    }

    static let endpoint = belongsTo(APIEndpointRecord.self)
}
