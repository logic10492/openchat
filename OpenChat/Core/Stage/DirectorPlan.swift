import Foundation

struct DirectorInput: Codable, Sendable, Equatable {
    let mode: DirectorMode
    let userInputRole: StageInputRole
    let currentInput: String
    let recentInstructionIds: [String]

    init(
        mode: DirectorMode,
        userInputRole: StageInputRole,
        currentInput: String,
        recentInstructionIds: [String] = []
    ) {
        self.mode = mode
        self.userInputRole = userInputRole
        self.currentInput = currentInput
        self.recentInstructionIds = recentInstructionIds
    }
}

enum SpeakerTurnIntent: String, Codable, Sendable, CaseIterable {
    case respondToUser
    case react
    case advanceScene
    case remainSilent
}

struct SpeakerTurn: Codable, Sendable, Equatable {
    let participantId: String?
    let characterCardId: String?
    let intent: SpeakerTurnIntent
    let maxTokens: Int?

    init(
        participantId: String? = nil,
        characterCardId: String? = nil,
        intent: SpeakerTurnIntent,
        maxTokens: Int? = nil
    ) {
        self.participantId = participantId
        self.characterCardId = characterCardId
        self.intent = intent
        self.maxTokens = maxTokens
    }
}

struct DirectorPlan: Codable, Sendable, Equatable {
    let mode: DirectorMode
    let stageInstructions: [StageInstruction]
    let speakerPlan: [SpeakerTurn]
    let diagnostics: DirectorDiagnostics

    init(
        mode: DirectorMode,
        stageInstructions: [StageInstruction] = [],
        speakerPlan: [SpeakerTurn] = [],
        diagnostics: DirectorDiagnostics = .empty
    ) {
        self.mode = mode
        self.stageInstructions = stageInstructions
        self.speakerPlan = speakerPlan
        self.diagnostics = diagnostics
    }
}
