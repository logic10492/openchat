import Foundation

struct StageSpeakerBlock: Sendable, Equatable {
    let participant: StageParticipantRecord
    let content: String
}

struct StageSpeakerBlockParser: Sendable {
    func parse(
        _ content: String,
        participants: [StageParticipantRecord]
    ) -> [StageSpeakerBlock] {
        let activeParticipants = participants
            .filter { $0.isActive && $0.visibilityValue == .present }
        guard !activeParticipants.isEmpty else { return [] }

        var blocks: [StageSpeakerBlock] = []
        var currentParticipant: StageParticipantRecord?
        var currentLines: [String] = []
        var sawExplicitMarker = false

        for rawLine in content.components(separatedBy: .newlines) {
            if isClosingMarker(rawLine) {
                appendCurrent(
                    participant: &currentParticipant,
                    lines: &currentLines,
                    blocks: &blocks
                )
                sawExplicitMarker = true
                continue
            }

            if let participant = participantMarker(rawLine, participants: activeParticipants) {
                appendCurrent(
                    participant: &currentParticipant,
                    lines: &currentLines,
                    blocks: &blocks
                )
                currentParticipant = participant
                currentLines = []
                sawExplicitMarker = true
                continue
            }

            if currentParticipant != nil {
                currentLines.append(rawLine)
            }
        }

        appendCurrent(
            participant: &currentParticipant,
            lines: &currentLines,
            blocks: &blocks
        )

        return sawExplicitMarker ? blocks : []
    }

    private func appendCurrent(
        participant: inout StageParticipantRecord?,
        lines: inout [String],
        blocks: inout [StageSpeakerBlock]
    ) {
        guard let resolved = participant else { return }
        let text = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            blocks.append(StageSpeakerBlock(participant: resolved, content: text))
        }
        participant = nil
        lines = []
    }

    private func isClosingMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "[/Speaker]" || trimmed == "[/speaker]" || trimmed == "</speaker>"
    }

    private func participantMarker(
        _ line: String,
        participants: [StageParticipantRecord]
    ) -> StageParticipantRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[Speaker:"), trimmed.hasSuffix("]") {
            let name = trimmed
                .dropFirst("[Speaker:".count)
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return resolve(name: name, participants: participants)
        }
        if trimmed.hasPrefix("[speaker:"), trimmed.hasSuffix("]") {
            let name = trimmed
                .dropFirst("[speaker:".count)
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return resolve(name: name, participants: participants)
        }
        if trimmed.hasPrefix("<speaker "), trimmed.hasSuffix(">"),
           let name = attribute(named: "name", in: trimmed) {
            return resolve(name: name, participants: participants)
        }
        if trimmed.hasSuffix(":") {
            let name = String(trimmed.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return resolve(name: name, participants: participants)
        }
        return nil
    }

    private func attribute(named attributeName: String, in marker: String) -> String? {
        let pattern = "\(attributeName)=\""
        guard let start = marker.range(of: pattern) else { return nil }
        let valueStart = start.upperBound
        guard let end = marker[valueStart...].firstIndex(of: "\"") else { return nil }
        return String(marker[valueStart..<end])
    }

    private func resolve(
        name: String,
        participants: [StageParticipantRecord]
    ) -> StageParticipantRecord? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return participants.first {
            $0.displayName.compare(
                normalized,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }
}
