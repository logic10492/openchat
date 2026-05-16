import Foundation

struct ToolUsePolicy: Sendable, Codable, Equatable {
    let allowedToolNames: Set<String>
    let allowNetwork: Bool
    let requireCitations: Bool

    static let disabled = ToolUsePolicy(
        allowedToolNames: [],
        allowNetwork: false,
        requireCitations: false
    )
}
