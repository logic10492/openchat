import Foundation

struct APIEndpointConfig: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String?
    let modelName: String
    let maxContextTokens: Int
    let apiMode: APIMode
    let providerDialect: APIProviderDialect

    init(
        baseURL: URL,
        apiKey: String?,
        modelName: String,
        maxContextTokens: Int,
        apiMode: APIMode = .chatCompletions,
        providerDialect: APIProviderDialect = .openAICompatible
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxContextTokens = maxContextTokens
        self.apiMode = apiMode
        self.providerDialect = providerDialect
    }

    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord) throws {
        try self.init(from: endpoint, model: model, apiKey: endpoint.apiKey)
    }

    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord, apiKey: String?) throws {
        guard let baseURL = URL(string: endpoint.baseURL) else {
            throw APIError.invalidURL(endpoint.baseURL)
        }
        self.init(
            baseURL: baseURL,
            apiKey: apiKey?.nilIfBlank,
            modelName: model.modelId,
            maxContextTokens: model.maxContextTokens,
            apiMode: model.apiModeValue,
            providerDialect: model.providerDialectValue
        )
    }

    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord, apiKeyStore: any APIKeyStore) throws {
        let storedKey = try apiKeyStore.readKey(endpointId: endpoint.id)
        try self.init(from: endpoint, model: model, apiKey: storedKey ?? endpoint.apiKey)
    }
}
