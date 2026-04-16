import Foundation

struct APIEndpointConfig: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String?
    let modelName: String
    let maxContextTokens: Int
    let apiMode: APIMode

    init(baseURL: URL, apiKey: String?, modelName: String, maxContextTokens: Int, apiMode: APIMode = .chatCompletions) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxContextTokens = maxContextTokens
        self.apiMode = apiMode
    }

    init(from record: APIEndpointRecord) throws {
        guard let baseURL = URL(string: record.baseURL) else {
            throw APIError.invalidURL(record.baseURL)
        }
        self.init(baseURL: baseURL, apiKey: record.apiKey, modelName: record.modelName, maxContextTokens: record.maxContextTokens, apiMode: record.apiModeValue)
    }
}
