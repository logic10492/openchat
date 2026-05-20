import Foundation

struct CharacterStateBackgroundSource: BackgroundSource {
    let sourceType: BackgroundSourceType = .characterState

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        guard let card = request.characterCard else { return [] }

        var sections: [String] = []
        append("Character", card.name, to: &sections)
        append("Personality", card.personality, to: &sections)
        append("Appearance", card.appearance, to: &sections)
        append("Physique", card.physique, to: &sections)
        append("Speech Style", card.speechStyle, to: &sections)
        append("Backstory", card.backstory, to: &sections)
        append("Scenario", card.scenario, to: &sections)

        if let activeSpeaker = request.stageContext?.activeSpeaker,
           activeSpeaker.characterCardId == card.id {
            append("Stage Role", "Active speaker: \(activeSpeaker.displayName)", to: &sections)
        }

        guard !sections.isEmpty else { return [] }
        return [
            BackgroundCandidate(
                id: "\(sourceType.rawValue):\(card.id)",
                sourceType: sourceType,
                sourceId: card.id,
                content: sections.joined(separator: "\n"),
                title: card.name,
                basePriority: 95,
                relevance: 0.95,
                recency: card.updatedAt,
                metadata: [
                    "sourceTable": CharacterCardRecord.databaseTableName,
                    "sourceId": card.id,
                    "characterCardId": card.id,
                    "stageId": request.stageContext?.stageId ?? "",
                    "reasons": "activeCharacterState",
                ].compactingEmptyValues()
            ),
        ]
    }

    private func append(_ label: String, _ value: String?, to sections: inout [String]) {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }
        sections.append("\(label): \(text)")
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
