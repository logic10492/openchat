import Foundation

enum BackgroundSourceType: String, Codable, Sendable, CaseIterable, Hashable {
    case memory
    case worldBook
    case characterState
    case conversationState
}

protocol BackgroundSourceTool: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var sourceType: BackgroundSourceType { get }
    func call(_ input: Input) async throws -> Output
}

struct BackgroundToolDiagnostics: Sendable {
    let sourceType: BackgroundSourceType
    let inputSummary: [String: String]
    let startedAt: Date
    let durationMilliseconds: Double?
    let fallback: String?
}

struct BackgroundRequest: Sendable {
    let conversation: ConversationRecord
    let characterCard: CharacterCardRecord?
    let worldBook: WorldBookRecord?
    let worldBookEntries: [WorldBookEntryRecord]
    let recentMessages: [MessageRecord]
    let stageContext: StageBackgroundContext?
    let currentInput: String
    let tokenBudget: Int
    let memoryLimit: Int
    let worldBookLimit: Int

    init(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        stageContext: StageBackgroundContext? = nil,
        currentInput: String,
        tokenBudget: Int,
        memoryLimit: Int = 10,
        worldBookLimit: Int = 10
    ) {
        self.conversation = conversation
        self.characterCard = characterCard
        self.worldBook = worldBook
        self.worldBookEntries = worldBookEntries
        self.recentMessages = recentMessages
        self.stageContext = stageContext
        self.currentInput = currentInput
        self.tokenBudget = tokenBudget
        self.memoryLimit = memoryLimit
        self.worldBookLimit = worldBookLimit
    }
}

struct StageBackgroundContext: Sendable, Equatable {
    let stageId: String
    let activeParticipants: [StageParticipantRecord]
    let activeSpeaker: StageParticipantRecord?
    let directorInstructions: [StageInstruction]

    init(
        stageId: String,
        activeParticipants: [StageParticipantRecord],
        activeSpeaker: StageParticipantRecord?,
        directorInstructions: [StageInstruction]
    ) {
        self.stageId = stageId
        self.activeParticipants = activeParticipants
        self.activeSpeaker = activeSpeaker
        self.directorInstructions = directorInstructions
    }

    init(stageTurnPlan: StageTurnPlan) {
        self.init(
            stageId: stageTurnPlan.stage.id,
            activeParticipants: stageTurnPlan.participants
                .filter { $0.isActive && $0.visibilityValue == .present }
                .sorted { $0.sortOrder < $1.sortOrder },
            activeSpeaker: stageTurnPlan.participant,
            directorInstructions: stageTurnPlan.visibleInstructions
        )
    }

    var activeCharacterCardIds: [String] {
        uniqueOrdered(activeParticipants.map(\.characterCardId))
    }

    var queryText: String {
        let participantLine = activeParticipants.map(\.displayName).joined(separator: ", ")
        let instructionText = directorInstructions
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return [
            participantLine.isEmpty ? nil : "Stage participants: \(participantLine)",
            activeSpeaker.map { "Active speaker: \($0.displayName)" },
            instructionText.isEmpty ? nil : "Director instructions:\n\(instructionText)",
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

protocol BackgroundSource: Sendable {
    var sourceType: BackgroundSourceType { get }
    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate]
}

struct BackgroundCandidate: Identifiable, Sendable {
    let id: String
    let sourceType: BackgroundSourceType
    let sourceId: String
    let content: String
    let title: String?
    let basePriority: Int
    let relevance: Double?
    let recency: Date?
    let metadata: [String: String]
}
