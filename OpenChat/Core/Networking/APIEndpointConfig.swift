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

    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord) throws {
        guard let baseURL = URL(string: endpoint.baseURL) else {
            throw APIError.invalidURL(endpoint.baseURL)
        }
        self.init(
            baseURL: baseURL,
            apiKey: endpoint.apiKey,
            modelName: model.modelId,
            maxContextTokens: model.maxContextTokens,
            apiMode: model.apiModeValue
        )
    }
}
