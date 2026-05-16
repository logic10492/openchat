import Foundation

struct MemoryReflectRequest: Sendable {
    let characterCardId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]

    init(
        characterCardId: String,
        task: MemoryReflectTask,
        sourceMemoryIds: [String]
    ) throws {
        let trimmedCharacterCardId = characterCardId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceIds = sourceMemoryIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedCharacterCardId.isEmpty else {
            throw MemoryReflectContractError.emptyCharacterCardId
        }
        guard !normalizedSourceIds.isEmpty else {
            throw MemoryReflectContractError.emptySourceMemoryIds
        }

        self.characterCardId = trimmedCharacterCardId
        self.task = task
        self.sourceMemoryIds = normalizedSourceIds
    }
}

struct MemoryReflectObservation: Sendable {
    let content: String
    let memoryType: MemoryType
    let basedOnMemoryIds: [String]
    let confidence: Double?
    let suggestedAction: MemoryReflectAction

    init(
        content: String,
        memoryType: MemoryType,
        basedOnMemoryIds: [String],
        confidence: Double? = nil,
        suggestedAction: MemoryReflectAction
    ) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBasedOnIds = basedOnMemoryIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedContent.isEmpty else {
            throw MemoryReflectContractError.emptyObservationContent
        }
        guard !normalizedBasedOnIds.isEmpty else {
            throw MemoryReflectContractError.emptyBasedOnMemoryIds
        }

        self.content = trimmedContent
        self.memoryType = memoryType
        self.basedOnMemoryIds = normalizedBasedOnIds
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.suggestedAction = suggestedAction
    }
}

enum MemoryReflectTask: String, Codable, CaseIterable, Sendable {
    case summarize
    case dedupe
    case resolveConflict = "resolve_conflict"
    case relationshipObservation = "relationship_observation"
}

enum MemoryReflectAction: String, Codable, CaseIterable, Sendable {
    case insertObservation = "insert_observation"
    case markDuplicate = "mark_duplicate"
    case needsUserReview = "needs_user_review"
}

enum MemoryEntryLinkRelation: String, Codable, CaseIterable, Sendable {
    case summarizes
    case duplicates
    case reinforces
}

enum MemoryReflectContractError: LocalizedError, Equatable, Sendable {
    case emptyCharacterCardId
    case emptySourceMemoryIds
    case emptyObservationContent
    case emptyBasedOnMemoryIds

    var errorDescription: String? {
        switch self {
        case .emptyCharacterCardId:
            "Memory reflect request must include a character card id."
        case .emptySourceMemoryIds:
            "Memory reflect request must include source memory ids."
        case .emptyObservationContent:
            "Memory reflect observation must include content."
        case .emptyBasedOnMemoryIds:
            "Memory reflect observation must include based-on memory ids."
        }
    }
}
