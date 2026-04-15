import Foundation

struct PromptAssembler {
    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        recentMessages: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview {
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let contextText = makeContextText(recentMessages: recentMessages, currentInput: currentInput)
        let systemPrompt = makeSystemPrompt(characterCard: characterCard)
        let characterDescription = buildCharacterDescription(characterCard)
        let scenario = makeScenario(conversation: conversation, characterCard: characterCard)
        let timeContext = makeTimeContext()
        let afterSystemEntries = makeTriggeredEntries(
            worldBook: worldBook,
            entries: worldBookEntries,
            contextText: contextText,
            position: .afterSystem
        )
        let beforeHistoryEntries = makeTriggeredEntries(
            worldBook: worldBook,
            entries: worldBookEntries,
            contextText: contextText,
            position: .beforeHistory
        )
        let exampleDialogs = makeExampleDialogs(characterCard: characterCard)

        let systemMessage = ChatMessage(role: "system", content: systemPrompt)
        let characterMessage = characterDescription.map { ChatMessage(role: "system", content: $0) }
        let scenarioMessage = scenario.map { ChatMessage(role: "system", content: $0) }
        let timeContextMessage = ChatMessage(role: "system", content: timeContext)
        let currentInputMessage = ChatMessage(role: "user", content: currentInput)

        let fixedTokens =
            TokenCounter.count(message: systemMessage) +
            (characterMessage.map { TokenCounter.count(message: $0) } ?? 0) +
            (scenarioMessage.map { TokenCounter.count(message: $0) } ?? 0) +
            TokenCounter.count(message: timeContextMessage) +
            (currentInput.isEmpty ? 0 : TokenCounter.count(message: currentInputMessage))
        let worldBookTokens = (afterSystemEntries + beforeHistoryEntries).reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent($1))) }
        let memoryTokens = memories.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent($1))) }
        let exampleTokens = exampleDialogs.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let tokenBudget = TokenBudget.calculate(
            totalBudget: totalBudget,
            fixedTokens: fixedTokens,
            exampleDialogsTokens: exampleTokens,
            worldBookTokens: worldBookTokens,
            memoryTokens: memoryTokens
        )

        let trimmedWorldBookEntries = trim(entries: afterSystemEntries + beforeHistoryEntries, within: tokenBudget.worldBookBudget)
        let trimmedAfterSystemEntries = trimmedWorldBookEntries.filter { $0.positionValue == .afterSystem }
        let trimmedBeforeHistoryEntries = trimmedWorldBookEntries.filter { $0.positionValue == .beforeHistory }
        let trimmedMemories = trim(memories: memories, within: tokenBudget.memoryBudget)
        let trimmedExampleDialogs = trim(messages: exampleDialogs, within: tokenBudget.exampleDialogsBudget)

        var messagesBeforeHistory: [ChatMessage] = [systemMessage]
        messagesBeforeHistory.append(contentsOf: trimmedAfterSystemEntries.map { ChatMessage(role: "system", content: makeWorldBookMessageContent($0)) })
        if let characterMessage {
            messagesBeforeHistory.append(characterMessage)
        }
        if let scenarioMessage {
            messagesBeforeHistory.append(scenarioMessage)
        }
        messagesBeforeHistory.append(timeContextMessage)
        if !trimmedMemories.isEmpty {
            messagesBeforeHistory.append(contentsOf: trimmedMemories.map { ChatMessage(role: "system", content: makeMemoryMessageContent($0)) })
        }
        messagesBeforeHistory.append(contentsOf: trimmedBeforeHistoryEntries.map { ChatMessage(role: "system", content: makeWorldBookMessageContent($0)) })
        messagesBeforeHistory.append(contentsOf: trimmedExampleDialogs)

        let actualFixedTokens = messagesBeforeHistory.reduce(0) { $0 + TokenCounter.count(message: $1) }
            + TokenCounter.count(message: currentInputMessage)
        let historyBudget = max(totalBudget - actualFixedTokens, 0)

        let tokenUsage = TokenUsageReport(
            totalBudget: totalBudget,
            systemPrompt: TokenCounter.count(message: systemMessage),
            characterDescription: characterMessage.map { TokenCounter.count(message: $0) } ?? 0,
            scenario: scenarioMessage.map { TokenCounter.count(message: $0) } ?? 0,
            timeContext: TokenCounter.count(message: timeContextMessage),
            worldBookEntries: trimmedWorldBookEntries.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent($1))) },
            memories: trimmedMemories.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent($1))) },
            exampleDialogs: trimmedExampleDialogs.reduce(0) { $0 + TokenCounter.count(message: $1) },
            history: 0,
            currentInput: TokenCounter.count(message: currentInputMessage),
            totalUsed: actualFixedTokens,
            remaining: historyBudget
        )

        return PromptAssemblyPreview(
            messagesBeforeHistory: messagesBeforeHistory,
            fixedTokens: actualFixedTokens,
            historyBudget: historyBudget,
            tokenUsage: tokenUsage,
            triggeredEntries: trimmedWorldBookEntries.map(\.id)
        )
    }

    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        recentMessages: [MessageRecord],
        processedHistory: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult {
        let context = preview(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            memories: memories,
            recentMessages: recentMessages,
            currentInput: currentInput,
            endpoint: endpoint
        )

        var messages = context.messagesBeforeHistory
        messages.append(contentsOf: processedHistory.map(\.chatMessage))
        messages.append(ChatMessage(role: "user", content: currentInput))

        let historyTokens = processedHistory.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let totalUsed = context.tokenUsage.totalUsed + historyTokens
        let usage = TokenUsageReport(
            totalBudget: context.tokenUsage.totalBudget,
            systemPrompt: context.tokenUsage.systemPrompt,
            characterDescription: context.tokenUsage.characterDescription,
            scenario: context.tokenUsage.scenario,
            timeContext: context.tokenUsage.timeContext,
            worldBookEntries: context.tokenUsage.worldBookEntries,
            memories: context.tokenUsage.memories,
            exampleDialogs: context.tokenUsage.exampleDialogs,
            history: historyTokens,
            currentInput: context.tokenUsage.currentInput,
            totalUsed: totalUsed,
            remaining: max(context.tokenUsage.totalBudget - totalUsed, 0)
        )
        return AssemblyResult(
            messages: messages,
            tokenUsage: usage,
            triggeredEntries: context.triggeredEntries
        )
    }

    static func buildCharacterDescription(_ card: CharacterCardRecord?) -> String? {
        guard let card else { return nil }

        let fields: [(String, String?)] = [
            ("Character", card.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Personality", card.personality?.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Appearance", card.appearance?.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Physique", card.physique?.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Speech style", card.speechStyle?.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("Backstory", card.backstory?.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]

        let lines: [String] = fields.compactMap { field in
            let label = field.0
            guard let value = field.1, !value.isEmpty else { return nil }
            return "\(label): \(value)"
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func makeWorldBookMessageContent(_ entry: WorldBookEntryRecord) -> String {
        "[World Book: \(entry.title)]\n\(entry.content)"
    }

    static func makeMemoryMessageContent(_ entry: MemoryEntryRecord) -> String {
        "[Memory — \(entry.memoryType)]\n\(entry.content)"
    }

    private static func makeTimeContext() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return "[Current Time: \(formatter.string(from: Date()))]"
    }

    private static func makeSystemPrompt(characterCard: CharacterCardRecord?) -> String {
        if let systemPrompt = characterCard?.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !systemPrompt.isEmpty {
            return systemPrompt
        }
        let trimmedName = characterCard?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let characterName = (trimmedName?.isEmpty ?? true) ? "the character" : (trimmedName ?? "the character")
        return "You are \(characterName), engaging in a roleplay conversation. Stay in character at all times. Respond naturally as \(characterName) would."
    }

    private static func makeScenario(conversation: ConversationRecord, characterCard: CharacterCardRecord?) -> String? {
        if let customScenario = conversation.customScenario?.trimmingCharacters(in: .whitespacesAndNewlines), !customScenario.isEmpty {
            return customScenario
        }
        if let scenario = characterCard?.scenario?.trimmingCharacters(in: .whitespacesAndNewlines), !scenario.isEmpty {
            return scenario
        }
        return nil
    }

    private static func makeTriggeredEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        contextText: String,
        position: WorldBookEntryPosition
    ) -> [WorldBookEntryRecord] {
        guard worldBook?.isEnabled ?? false else { return [] }
        return KeywordMatcher.triggeredEntries(entries, contextText: contextText, position: position)
    }

    private static func makeExampleDialogs(characterCard: CharacterCardRecord?) -> [ChatMessage] {
        guard let characterCard else { return [] }
        return (try? characterCard.exampleDialogMessages()) ?? []
    }

    private static func makeContextText(recentMessages: [MessageRecord], currentInput: String) -> String {
        let recentText = recentMessages.suffix(5).map(\.content).joined(separator: "\n")
        return [recentText, currentInput].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func trim(entries: [WorldBookEntryRecord], within budget: Int) -> [WorldBookEntryRecord] {
        guard budget > 0 else { return [] }
        var result: [WorldBookEntryRecord] = []
        var used = 0
        for entry in entries {
            let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent(entry)))
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(entry)
            used += tokens
        }
        return result
    }

    private static func trim(messages: [ChatMessage], within budget: Int) -> [ChatMessage] {
        guard budget > 0 else { return [] }
        var result: [ChatMessage] = []
        var used = 0
        for message in messages {
            let tokens = TokenCounter.count(message: message)
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(message)
            used += tokens
        }
        return result
    }

    private static func trim(memories: [MemoryEntryRecord], within budget: Int) -> [MemoryEntryRecord] {
        guard budget > 0 else { return [] }
        var result: [MemoryEntryRecord] = []
        var used = 0
        for entry in memories.sorted(by: { $0.importance > $1.importance }) {
            let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent(entry)))
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(entry)
            used += tokens
        }
        return result
    }
}
