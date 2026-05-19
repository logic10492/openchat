import Foundation

struct DirectorDiagnostics: Codable, Sendable, Equatable {
    let warnings: [String]
    let omittedInstructionIds: [String]
    let policyProfile: [String: String]
    let metadata: [String: String]

    init(
        warnings: [String] = [],
        omittedInstructionIds: [String] = [],
        policyProfile: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.warnings = warnings
        self.omittedInstructionIds = omittedInstructionIds
        self.policyProfile = policyProfile
        self.metadata = metadata
    }

    static let empty = DirectorDiagnostics()
}

enum StagePromptLayer: String, Codable, Sendable, CaseIterable {
    case stageIdentity
    case characterPersonas
    case stableConversationState
    case currentBackground
    case directorInstructions
    case currentTurn
}

struct StagePromptLayerPlan: Codable, Sendable, Equatable {
    let layers: [StagePromptLayer]
    let directorInstructionIds: [String]

    init(
        layers: [StagePromptLayer] = StagePromptLayerPlan.defaultLayerOrder,
        directorInstructionIds: [String] = []
    ) {
        self.layers = layers
        self.directorInstructionIds = directorInstructionIds
    }

    static let defaultLayerOrder: [StagePromptLayer] = [
        .stageIdentity,
        .characterPersonas,
        .stableConversationState,
        .currentBackground,
        .directorInstructions,
        .currentTurn,
    ]
}
