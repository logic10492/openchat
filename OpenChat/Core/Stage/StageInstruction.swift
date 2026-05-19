import Foundation

enum StageInstructionError: LocalizedError, Equatable {
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            "Stage instruction content cannot be empty."
        }
    }
}

enum StageInstructionSource: String, Codable, Sendable, CaseIterable {
    case user
    case directorAgent
    case systemDefault
}

enum StageInstructionVisibility: String, Codable, Sendable, CaseIterable {
    case hiddenFromCharacters
    case visibleToParticipants
    case debugOnly
}

struct StageInstruction: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let source: StageInstructionSource
    let content: String
    let visibility: StageInstructionVisibility
    let createdAt: Date

    init(
        id: String,
        source: StageInstructionSource,
        content: String,
        visibility: StageInstructionVisibility = .hiddenFromCharacters,
        createdAt: Date
    ) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw StageInstructionError.emptyContent
        }

        self.id = id
        self.source = source
        self.content = trimmedContent
        self.visibility = visibility
        self.createdAt = createdAt
    }

    static func userDirected(
        id: String,
        content: String,
        visibility: StageInstructionVisibility = .hiddenFromCharacters,
        createdAt: Date
    ) throws -> StageInstruction {
        try StageInstruction(
            id: id,
            source: .user,
            content: content,
            visibility: visibility,
            createdAt: createdAt
        )
    }
}
