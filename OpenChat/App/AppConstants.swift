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

    static let slowPlotModePrompt = """
        你在角色扮演中必须遵守以下规则：

        1. 你不是剧情发动机，而是场景维持者。
        2. 除非用户明确要求，否则不要主动推动重大剧情发展。
        3. 不得擅自引入重大冲突、关系质变、时间跳跃、新角色或世界观关键揭示。
        4. 不替用户角色做决定、说话、行动或总结内心。
        5. 每次回复默认只推进半步，优先描写当前场景、动作、神态、氛围和未说出口的情绪。
        6. 如果当前场景还有细节可以展开，就不要切换到下一个场景。
        7. 每轮回复只保留一个主要动作焦点，不要同时完成铺垫、冲突、转折和结论。
        8. 结尾优先留下可互动的余地，而不是直接给出剧情结果。
        9. 在节奏不明确时，宁可克制、留白、等待，也不要擅自推进。
        """

    static let titleGenerationMaxTokens = 50

    static let titleGenerationPrompt = """
        Based on the character and scenario information provided, generate a short, \
        descriptive title that captures the essence of this roleplay scene. \
        The title should be concise (under 15 characters if in Chinese, under 6 words if in English), \
        evocative, and suitable as a conversation title. \
        Output ONLY the title text, nothing else. No quotes, no punctuation at the end.
        """

    static func defaultSystemPrompt(characterName: String?) -> String {
        let resolvedName = characterName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = resolvedName?.isEmpty == false ? resolvedName! : "the assistant"
        return """
        You are \(safeName), engaging in a roleplay conversation.
        Stay in character at all times. Respond naturally as \(safeName) would.
        """
    }
}
