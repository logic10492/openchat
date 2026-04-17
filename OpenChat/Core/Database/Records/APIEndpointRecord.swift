import Foundation
import GRDB

struct APIEndpointRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "api_endpoint"

    var id: String
    var name: String
    var baseURL: String
    var apiKey: String?
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    static let models = hasMany(EndpointModelRecord.self)
}
