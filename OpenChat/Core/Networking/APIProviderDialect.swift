import Foundation

enum APIProviderDialect: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAICompatible
    case deepSeekV4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            String(localized: "OpenAI Compatible")
        case .deepSeekV4:
            String(localized: "DeepSeek V4")
        }
    }

    static func inferred(baseURL: URL, modelId: String) -> APIProviderDialect {
        let host = baseURL.host?.lowercased() ?? ""
        let normalizedModel = modelId.lowercased()
        if normalizedModel == "deepseek-v4-flash" || normalizedModel == "deepseek-v4-pro" {
            return .deepSeekV4
        }
        if host.contains("deepseek.com"), normalizedModel.hasPrefix("deepseek-v4-") {
            return .deepSeekV4
        }
        return .openAICompatible
    }

    static func defaultContextTokens(baseURL: URL, modelId: String, reportedContextLength: Int?) -> Int {
        if let reportedContextLength {
            return reportedContextLength
        }
        return inferred(baseURL: baseURL, modelId: modelId) == .deepSeekV4 ? 1_000_000 : 4096
    }
}

enum ReasoningEffort: String, Codable, Sendable, CaseIterable, Identifiable {
    case high
    case max

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high:
            String(localized: "High")
        case .max:
            String(localized: "Max")
        }
    }
}
