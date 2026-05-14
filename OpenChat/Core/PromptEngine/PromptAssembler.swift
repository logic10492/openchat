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
        let triggeredWorldBookEntries = makeTriggeredEntries(
            worldBook: worldBook,
            entries: worldBookEntries,
            contextText: contextText
        )
        let exampleDialogs = makeExampleDialogs(characterCard: characterCard)

        let systemMessage = ChatMessage(role: "system", content: systemPrompt)
        let characterMessage = characterDescription.map { ChatMessage(role: "system", content: $0) }
        let scenarioMessage = scenario.map { ChatMessage(role: "system", content: $0) }
        let slowPlotMessage: ChatMessage? = conversation.slowPlotMode
            ? ChatMessage(role: "system", content: AppConstants.slowPlotModePrompt)
            : nil
        let stableIdentityMessages = [
            systemMessage,
            characterMessage,
            scenarioMessage,
            slowPlotMessage,
        ].compactMap { $0 }
        let currentInputMessage = ChatMessage(role: "user", content: currentInput)
        let currentTurnMessage = ChatMessage(
            role: "user",
            content: makeCurrentTurnContent(currentInput: currentInput, timeContext: timeContext)
        )

        let fixedTokens =
            stableIdentityMessages.reduce(0) { $0 + TokenCounter.count(message: $1) } +
            TokenCounter.count(message: currentTurnMessage)
        let worldBookTokens = triggeredWorldBookEntries.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent($1))) }
        let memoryTokens = memories.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent($1))) }
        let exampleTokens = exampleDialogs.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let tokenBudget = TokenBudget.calculate(
            totalBudget: totalBudget,
            fixedTokens: fixedTokens,
            exampleDialogsTokens: exampleTokens,
            worldBookTokens: worldBookTokens,
            memoryTokens: memoryTokens
        )

        let trimmedExampleDialogs = trim(messages: exampleDialogs, within: tokenBudget.exampleDialogsBudget)
        let trimmedWorldBookEntries = trim(entries: triggeredWorldBookEntries, within: tokenBudget.worldBookBudget)
        let trimmedMemories = trim(memories: memories, within: tokenBudget.memoryBudget)

        let exampleDialogsBlock = makeExampleDialogsBlock(trimmedExampleDialogs)
        let worldBookBlock = makeWorldBookBlock(trimmedWorldBookEntries)
        let memoryBlock = makeMemoryBlock(trimmedMemories)
        let currentTurnContextMessages = [
            exampleDialogsBlock,
            worldBookBlock,
            memoryBlock,
        ].compactMap { $0 }

        let actualFixedTokens =
            stableIdentityMessages.reduce(0) { $0 + TokenCounter.count(message: $1) } +
            currentTurnContextMessages.reduce(0) { $0 + TokenCounter.count(message: $1) } +
            TokenCounter.count(message: currentTurnMessage)
        let historyBudget = max(totalBudget - actualFixedTokens, 0)

        let tokenUsage = TokenUsageReport(
            totalBudget: totalBudget,
            systemPrompt: TokenCounter.count(message: systemMessage),
            characterDescription: characterMessage.map { TokenCounter.count(message: $0) } ?? 0,
            scenario: scenarioMessage.map { TokenCounter.count(message: $0) } ?? 0,
            slowPlotDirective: slowPlotMessage.map { TokenCounter.count(message: $0) } ?? 0,
            timeContext: TokenCounter.count(timeContext),
            worldBookEntries: worldBookBlock.map { TokenCounter.count(message: $0) } ?? 0,
            memories: memoryBlock.map { TokenCounter.count(message: $0) } ?? 0,
            exampleDialogs: exampleDialogsBlock.map { TokenCounter.count(message: $0) } ?? 0,
            history: 0,
            currentInput: TokenCounter.count(message: currentInputMessage),
            totalUsed: actualFixedTokens,
            remaining: historyBudget
        )

        return PromptAssemblyPreview(
            stableIdentityMessages: stableIdentityMessages,
            currentTurnContextMessages: currentTurnContextMessages,
            currentTurnMessage: currentTurnMessage,
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

        var messages = context.stableIdentityMessages
        messages.append(contentsOf: processedHistory.map(\.chatMessage))
        messages.append(contentsOf: context.currentTurnContextMessages)
        messages.append(context.currentTurnMessage)

        let historyTokens = processedHistory.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let totalUsed = context.tokenUsage.totalUsed + historyTokens
        let usage = TokenUsageReport(
            totalBudget: context.tokenUsage.totalBudget,
            systemPrompt: context.tokenUsage.systemPrompt,
            characterDescription: context.tokenUsage.characterDescription,
            scenario: context.tokenUsage.scenario,
            slowPlotDirective: context.tokenUsage.slowPlotDirective,
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

    private static func makeExampleDialogsBlock(_ messages: [ChatMessage]) -> ChatMessage? {
        guard !messages.isEmpty else { return nil }
        let bodyLines: [String] = messages.map { message in
            let label = message.role == "assistant" ? "Assistant" : "User"
            return "\(label): \(message.content)"
        }
        let body = bodyLines.joined(separator: "\n")
        return ChatMessage(role: "system", content: "[Example Dialogs]\n\(body)\n[/Example Dialogs]")
    }

    private static func makeWorldBookBlock(_ entries: [WorldBookEntryRecord]) -> ChatMessage? {
        guard !entries.isEmpty else { return nil }
        let body = entries.map { makeWorldBookMessageContent($0) }.joined(separator: "\n\n")
        return ChatMessage(role: "system", content: "[World Book Entries]\n\(body)\n[/World Book Entries]")
    }

    private static func makeMemoryBlock(_ memories: [MemoryEntryRecord]) -> ChatMessage? {
        guard !memories.isEmpty else { return nil }
        let body = memories.map { makeMemoryMessageContent($0) }.joined(separator: "\n\n")
        return ChatMessage(role: "system", content: "[Memories]\n\(body)\n[/Memories]")
    }

    private static func makeCurrentTurnContent(currentInput: String, timeContext: String) -> String {
        let trimmedInput = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return timeContext }
        return "\(trimmedInput)\n\n\(timeContext)"
    }

    private static func makeTimeContext() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "[Time] \(formatter.string(from: Date())) [/Time]"
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
        contextText: String
    ) -> [WorldBookEntryRecord] {
        guard worldBook?.isEnabled ?? false else { return [] }
        return KeywordMatcher.triggeredEntries(entries, contextText: contextText)
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
        guard !entries.isEmpty else { return [] }
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
        guard !messages.isEmpty else { return [] }
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
        guard !memories.isEmpty else { return [] }
        var result: [MemoryEntryRecord] = []
        var used = 0
        for entry in memories {
            let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent(entry)))
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(entry)
            used += tokens
        }
        return result
    }
}
