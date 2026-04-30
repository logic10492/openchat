import Foundation

enum CompressionMode: String, Codable, CaseIterable, Sendable {
    case standard
    case highIntelligence

    var displayName: String {
        switch self {
        case .standard:
            return String(localized: "Standard")
        case .highIntelligence:
            return String(localized: "High Intelligence")
        }
    }
}
