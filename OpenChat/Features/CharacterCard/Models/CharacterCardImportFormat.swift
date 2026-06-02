import Foundation

enum CharacterCardImportError: LocalizedError, Equatable {
    case invalidJSON
    case unsupportedFormat
    case missingName

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            String(localized: "Character card JSON is invalid.")
        case .unsupportedFormat:
            String(localized: "Character card format is not supported.")
        case .missingName:
            String(localized: "Imported character card is missing a name.")
        }
    }
}

struct CharacterCardImportFormat {
    struct ParsedCard: Identifiable, Sendable {
        let id = UUID()
        var name: String
        var personality: String?
        var appearance: String?
        var physique: String?
        var speechStyle: String?
        var backstory: String?
        var systemPrompt: String?
        var scenario: String?
        var exampleDialogs: [ChatMessage]
        var creatorNotes: String?
        var tags: [String]
        var warnings: [String]

        var formatSummary: String {
            if warnings.isEmpty {
                String(localized: "Ready to import")
            } else {
                warnings.joined(separator: "\n")
            }
        }
    }

    static func parse(text: String) throws -> ParsedCard {
        guard let data = text.data(using: .utf8) else {
            throw CharacterCardImportError.invalidJSON
        }

        do {
            let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
            if probe.type == "openchat_character_card" {
                return try parseOpenChat(data: data)
            }
            throw CharacterCardImportError.unsupportedFormat
        } catch let error as CharacterCardImportError {
            throw error
        } catch {
            throw CharacterCardImportError.invalidJSON
        }
    }

    private static func parseOpenChat(data: Data) throws -> ParsedCard {
        let envelope = try JSONDecoder().decode(OpenChatEnvelope.self, from: data)
        let card = envelope.data
        guard let name = card.name.nilIfBlank else {
            throw CharacterCardImportError.missingName
        }

        return ParsedCard(
            name: name,
            personality: normalizedText(card.personality),
            appearance: normalizedText(card.appearance),
            physique: normalizedText(card.physique),
            speechStyle: normalizedText(card.speechStyle),
            backstory: normalizedText(card.backstory),
            systemPrompt: normalizedText(card.systemPrompt),
            scenario: normalizedText(card.scenario),
            exampleDialogs: card.exampleDialogs ?? [],
            creatorNotes: normalizedText(card.creatorNotes),
            tags: normalizedTags(card.tags ?? []),
            warnings: []
        )
    }

    private static func normalizedText(_ value: String?) -> String? {
        value.flatMap { $0.nilIfBlank }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.compactMap { $0.nilIfBlank })).sorted()
    }
}

private struct FormatProbe: Decodable {
    var type: String?
}

private struct OpenChatEnvelope: Decodable {
    var formatVersion: Int?
    var type: String
    var data: OpenChatCardData
}

private struct OpenChatCardData: Decodable {
    var name: String
    var personality: String?
    var appearance: String?
    var physique: String?
    var speechStyle: String?
    var backstory: String?
    var systemPrompt: String?
    var scenario: String?
    var exampleDialogs: [ChatMessage]?
    var creatorNotes: String?
    var tags: [String]?
}
