import Foundation

enum BackgroundSourceType: String, Codable, Sendable, CaseIterable, Hashable {
    case memory
    case worldBook
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
        self.currentInput = currentInput
        self.tokenBudget = tokenBudget
        self.memoryLimit = memoryLimit
        self.worldBookLimit = worldBookLimit
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
