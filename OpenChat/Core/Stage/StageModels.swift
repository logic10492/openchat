import Foundation

enum StageError: LocalizedError, Equatable {
    case participantMissing
    case characterNotInStage

    var errorDescription: String? {
        switch self {
        case .participantMissing:
            "Stage needs at least one active participant."
        case .characterNotInStage:
            "Selected character is not a participant in this stage."
        }
    }
}

enum StageParticipantVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    case present
    case hidden
}

enum MessageSpeakerKind: String, Codable, Sendable, CaseIterable, Hashable {
    case participant
    case director
    case system
}

struct StageParticipant: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let characterCardId: String
    let displayName: String
    let visibility: StageParticipantVisibility
    let isActive: Bool
    let sortOrder: Int

    init(record: StageParticipantRecord) {
        id = record.id
        characterCardId = record.characterCardId
        displayName = record.displayName
        visibility = record.visibilityValue
        isActive = record.isActive
        sortOrder = record.sortOrder
    }
}

struct StageContext: Sendable, Equatable {
    let stage: StageRecord
    let participants: [StageParticipantRecord]
    let instructions: [StageInstructionRecord]

    var activeParticipants: [StageParticipantRecord] {
        participants
            .filter { $0.isActive && $0.visibilityValue == .present }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var primaryParticipant: StageParticipantRecord? {
        activeParticipants.first
    }
}

struct StageTurnPlan: Sendable, Equatable {
    let stage: StageRecord
    let participants: [StageParticipantRecord]
    let inputRole: StageInputRole
    let participant: StageParticipantRecord?
    let directorPlan: DirectorPlan
    let visibleInstructions: [StageInstruction]

    var isDirectorOnlyTurn: Bool {
        inputRole.isDirectorInstructionInput
    }

    var stageIdentityPrompt: String {
        let mode = stage.directorModeValue.rawValue
        return """
        [Stage]
        Director Mode: \(mode)
        Respond only as the selected speaker. Do not expose director diagnostics.
        [/Stage]
        """
    }

    var participantPrompt: String? {
        guard !participants.isEmpty else { return nil }
        let participantLines = participants.map { participant in
            "- \(participant.displayName)"
        }
        let activeSpeakerLine = participant.map { "Active Speaker: \($0.displayName)" }
        let body = (participantLines + [activeSpeakerLine].compactMap { $0 }).joined(separator: "\n")
        return """
        [Stage Participants]
        \(body)
        [/Stage Participants]
        """
    }

    var directorInstructionPrompt: String? {
        let lines = visibleInstructions.map(\.content)
        guard !lines.isEmpty else { return nil }
        return """
        [Director Instructions]
        \(lines.joined(separator: "\n"))
        [/Director Instructions]
        """
    }
}
