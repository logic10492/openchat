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
            if probe.spec == "chara_card_v2" {
                return try parseSillyTavernV2(data: data)
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

    private static func parseSillyTavernV2(data: Data) throws -> ParsedCard {
        let envelope = try JSONDecoder().decode(SillyTavernV2Envelope.self, from: data)
        let card = envelope.data
        guard let name = card.name.nilIfBlank else {
            throw CharacterCardImportError.missingName
        }

        let personality = joinedNonBlank([card.description, card.personality], separator: "\n\n")
        let firstMessage = normalizedText(card.firstMessage).map { ChatMessage(role: "assistant", content: $0) }
        let exampleResult = parseSillyTavernExamples(card.messageExamples)
        let dialogs = [firstMessage].compactMap { $0 } + exampleResult.messages
        let warnings = exampleResult.hasRawFallback
            ? [String(localized: "Message examples were imported as raw text.")]
            : []

        return ParsedCard(
            name: name,
            personality: personality,
            appearance: nil,
            physique: nil,
            speechStyle: nil,
            backstory: nil,
            systemPrompt: normalizedText(card.systemPrompt),
            scenario: normalizedText(card.scenario),
            exampleDialogs: dialogs,
            creatorNotes: normalizedText(card.creatorNotes),
            tags: normalizedTags(card.tags ?? []),
            warnings: warnings
        )
    }

    private static func parseSillyTavernExamples(_ text: String?) -> SillyTavernExampleParseResult {
        guard let text = text?.nilIfBlank else {
            return SillyTavernExampleParseResult(messages: [], hasRawFallback: false)
        }

        let normalized = text
            .replacingOccurrences(of: "<START>", with: "\n")
            .replacingOccurrences(of: "{{user}}:", with: "User:", options: .caseInsensitive)
            .replacingOccurrences(of: "{{char}}:", with: "Assistant:", options: .caseInsensitive)

        var hasRawFallback = false
        let messages = normalized
            .components(separatedBy: .newlines)
            .compactMap { line -> ChatMessage? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if let content = content(after: "User:", in: trimmed) {
                    return ChatMessage(role: "user", content: content)
                }
                if let content = content(after: "Assistant:", in: trimmed) {
                    return ChatMessage(role: "assistant", content: content)
                }
                hasRawFallback = true
                return ChatMessage(role: "assistant", content: trimmed)
            }

        return SillyTavernExampleParseResult(messages: messages, hasRawFallback: hasRawFallback)
    }

    private static func content(after prefix: String, in line: String) -> String? {
        guard line.localizedCaseInsensitiveContains(prefix),
              line.lowercased().hasPrefix(prefix.lowercased()) else {
            return nil
        }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private static func joinedNonBlank(_ values: [String?], separator: String) -> String? {
        let parts = values.compactMap(normalizedText)
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    private static func normalizedText(_ value: String?) -> String? {
        value.flatMap { $0.nilIfBlank }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.compactMap { $0.nilIfBlank })).sorted()
    }
}

private struct SillyTavernExampleParseResult {
    var messages: [ChatMessage]
    var hasRawFallback: Bool
}

private struct FormatProbe: Decodable {
    var type: String?
    var spec: String?
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

private struct SillyTavernV2Envelope: Decodable {
    var spec: String
    var specVersion: String?
    var data: SillyTavernV2Data

    enum CodingKeys: String, CodingKey {
        case spec
        case specVersion = "spec_version"
        case data
    }
}

private struct SillyTavernV2Data: Decodable {
    var name: String
    var description: String?
    var personality: String?
    var scenario: String?
    var firstMessage: String?
    var messageExamples: String?
    var systemPrompt: String?
    var creatorNotes: String?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case personality
        case scenario
        case firstMessage = "first_mes"
        case messageExamples = "mes_example"
        case systemPrompt = "system_prompt"
        case creatorNotes = "creator_notes"
        case tags
    }
}
