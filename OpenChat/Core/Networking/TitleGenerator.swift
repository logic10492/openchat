import Foundation
import os.log

private let logger = Logger(subsystem: "com.openchat", category: "TitleGenerator")

struct TitleGenerator: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Generates a short, descriptive title for a conversation based on the scenario and character context.
    ///
    /// Uses an independent context window — only the title-generation system prompt and a brief
    /// summary of the scenario/character are sent to the API. No conversation history is included.
    func generateTitle(
        scenario: String?,
        characterCard: CharacterCardRecord?,
        userMessage: String,
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) async throws -> String {
        let messages = buildPrompt(scenario: scenario, characterCard: characterCard, userMessage: userMessage)
        let titleParameters = ModelParameters(
            temperature: parameters.temperature,
            topP: parameters.topP,
            maxTokens: AppConstants.titleGenerationMaxTokens
        )

        let response = try await apiClient.sendMessage(
            messages: messages,
            endpoint: endpoint,
            parameters: titleParameters
        )

        guard let rawTitle = response.choices.first?.message.content else {
            throw TitleGenerationError.emptyResponse
        }

        let cleaned = cleanTitle(rawTitle)
        guard !cleaned.isEmpty else {
            throw TitleGenerationError.emptyResponse
        }

        logger.info("Generated title: \(cleaned)")
        return cleaned
    }

    // MARK: - Prompt Construction

    func buildPrompt(
        scenario: String?,
        characterCard: CharacterCardRecord?,
        userMessage: String
    ) -> [ChatMessage] {
        var messages: [ChatMessage] = [
            ChatMessage(role: "system", content: AppConstants.titleGenerationPrompt)
        ]

        var contextParts: [String] = []

        if let name = characterCard?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            contextParts.append("Character: \(name)")
        }

        if let scenario = scenario?.trimmingCharacters(in: .whitespacesAndNewlines), !scenario.isEmpty {
            contextParts.append("Scenario: \(scenario)")
        }

        contextParts.append("First message: \(userMessage)")

        let userContent = contextParts.joined(separator: "\n")
        messages.append(ChatMessage(role: "user", content: userContent))

        return messages
    }

    // MARK: - Title Cleanup

    private func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding quotes (matching pairs)
        let quotePairs: [(String, String)] = [
            ("\"", "\""), ("'", "'"),
            ("\u{201C}", "\u{201D}"),
            ("\u{2018}", "\u{2019}"),
        ]
        for (open, close) in quotePairs {
            if title.hasPrefix(open) && title.hasSuffix(close) && title.count > 2 {
                title = String(title.dropFirst(open.count).dropLast(close.count))
                break
            }
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to a reasonable length
        if title.count > 30 {
            let index = title.index(title.startIndex, offsetBy: 30)
            title = String(title[..<index]) + "…"
        }

        return title
    }
}

// MARK: - Error

enum TitleGenerationError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            String(localized: "Title generation returned an empty response.")
        }
    }
}
