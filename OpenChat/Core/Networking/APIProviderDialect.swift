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
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    static let openAICompatibleCases: [ReasoningEffort] = [.none, .low, .medium, .high, .xhigh]
    static let deepSeekV4Cases: [ReasoningEffort] = [.high, .max]

    func requestValue(for providerDialect: APIProviderDialect) -> String {
        switch providerDialect {
        case .openAICompatible:
            return self == .max ? ReasoningEffort.xhigh.rawValue : rawValue
        case .deepSeekV4:
            return self == .max ? ReasoningEffort.max.rawValue : ReasoningEffort.high.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .none:
            String(localized: "None")
        case .minimal:
            String(localized: "Minimal")
        case .low:
            String(localized: "Low")
        case .medium:
            String(localized: "Medium")
        case .high:
            String(localized: "High")
        case .xhigh:
            String(localized: "X High")
        case .max:
            String(localized: "Max")
        }
    }
}
