import Foundation

enum AppConstants {
    static let defaultBundleIdentifier = "com.openchat.app"
    static let databaseFileName = "database.sqlite"
    static let defaultModelName = "gpt-4o-mini"
    static let defaultMaxContextTokens = 131_072
    static let contextRatio = 0.4
    static let defaultTemperature = 0.8
    static let defaultTopP = 0.95
    static let defaultContextStrategy = ContextStrategy.truncation

    static func defaultSystemPrompt(characterName: String?) -> String {
        let resolvedName = characterName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = resolvedName?.isEmpty == false ? resolvedName! : "the assistant"
        return """
        You are \(safeName), engaging in a roleplay conversation.
        Stay in character at all times. Respond naturally as \(safeName) would.
        """
    }
}
