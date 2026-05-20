import Foundation

struct ConversationStateBackgroundSource: BackgroundSource {
    let sourceType: BackgroundSourceType = .conversationState

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        let recentTurns = request.recentMessages
            .suffix(6)
            .map { message in
                let speaker = message.speakerName?.nilIfBlank ?? message.role
                return "\(speaker): \(message.content)"
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let stageLines = makeStageLines(request.stageContext)
        let sections = [
            "Conversation: \(request.conversation.title)",
            request.conversation.customScenario?.nilIfBlank.map { "Scenario Override: \($0)" },
            stageLines.isEmpty ? nil : "Stage State:\n\(stageLines.joined(separator: "\n"))",
            recentTurns.isEmpty ? nil : "Recent Turns:\n\(recentTurns.joined(separator: "\n"))",
        ].compactMap { $0 }

        guard !sections.isEmpty else { return [] }
        return [
            BackgroundCandidate(
                id: "\(sourceType.rawValue):\(request.conversation.id)",
                sourceType: sourceType,
                sourceId: request.conversation.id,
                content: sections.joined(separator: "\n"),
                title: request.conversation.title,
                basePriority: 90,
                relevance: 0.9,
                recency: request.conversation.updatedAt,
                metadata: [
                    "sourceTable": ConversationRecord.databaseTableName,
                    "sourceId": request.conversation.id,
                    "conversationId": request.conversation.id,
                    "stageId": request.stageContext?.stageId ?? "",
                    "reasons": "conversationState",
                ].compactingEmptyValues()
            ),
        ]
    }

    private func makeStageLines(_ stageContext: StageBackgroundContext?) -> [String] {
        guard let stageContext else { return [] }
        let participantLine = stageContext.activeParticipants
            .map(\.displayName)
            .joined(separator: ", ")
            .nilIfBlank
        let instructionLine = stageContext.directorInstructions
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .nilIfBlank

        return [
            participantLine.map { "Participants: \($0)" },
            stageContext.activeSpeaker.map { "Active Speaker: \($0.displayName)" },
            instructionLine.map { "Director Instructions:\n\($0)" },
        ].compactMap { $0 }
    }
}

private extension Dictionary where Key == String, Value == String {
    func compactingEmptyValues() -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in self where !value.isEmpty {
            result[key] = value
        }
        return result
    }
}
