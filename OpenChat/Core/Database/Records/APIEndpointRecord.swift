import Foundation
import GRDB

struct APIEndpointRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "api_endpoint"

    var id: String
    var name: String
    var baseURL: String
    var apiKey: String?
    var modelName: String
    var maxContextTokens: Int
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date
}
