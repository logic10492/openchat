import Foundation

struct PromptAssembler {
    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        recentMessages: [MessageRecord],
        stageTurnPlan: StageTurnPlan? = nil,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview {
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let contextText = makeContextText(recentMessages: recentMessages, currentInput: currentInput)
        let selectedWorldBookEntries = selectWorldBookEntries(
            worldBook: worldBook,
            entries: worldBookEntries,
            contextText: contextText,
            selectionMode: .keywordTriggered
        )
        return preview(
            conversation: conversation,
            characterCard: characterCard,
            selectedWorldBookEntries: selectedWorldBookEntries,
            memories: memories,
            stageTurnPlan: stageTurnPlan,
            currentInput: currentInput,
            endpoint: endpoint,
            totalBudget: totalBudget
        )
    }

    static func previewWithPreselectedWorldBookEntries(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        stageTurnPlan: StageTurnPlan? = nil,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview {
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let selectedWorldBookEntries = selectWorldBookEntries(
            worldBook: worldBook,
            entries: worldBookEntries,
            contextText: "",
            selectionMode: .preselected
        )
        return preview(
            conversation: conversation,
            characterCard: characterCard,
            selectedWorldBookEntries: selectedWorldBookEntries,
            memories: memories,
            stageTurnPlan: stageTurnPlan,
            currentInput: currentInput,
            endpoint: endpoint,
            totalBudget: totalBudget
        )
    }

    private static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        selectedWorldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord],
        stageTurnPlan: StageTurnPlan? = nil,
        currentInput: String,
        endpoint: APIEndpointConfig,
        totalBudget: Int
    ) -> PromptAssemblyPreview {
        let systemPrompt = makeSystemPrompt(characterCard: characterCard)
        let characterDescription = buildCharacterDescription(characterCard)
        let scenario = makeScenario(conversation: conversation, characterCard: characterCard)
        let timeContext = makeTimeContext()
        let exampleDialogs = makeExampleDialogs(characterCard: characterCard)
        let worldBookItems = selectedWorldBookEntries.map {
            BackgroundPromptItem(
                id: $0.id,
                sourceType: .worldBook,
                title: $0.title,
                label: $0.title,
                content: $0.content,
                estimatedTokens: TokenCounter.count(makeWorldBookMessageContent($0))
            )
        }
        let memoryItems = memories.map {
            BackgroundPromptItem(
                id: $0.id,
                sourceType: .memory,
                title: $0.memoryType,
                label: $0.memoryType,
                content: $0.content,
                estimatedTokens: TokenCounter.count(makeMemoryMessageContent($0))
            )
        }

        return preview(
            systemPrompt: systemPrompt,
            stageTurnPlan: stageTurnPlan,
            characterDescription: characterDescription,
            scenario: scenario,
            slowPlotMode: conversation.slowPlotMode,
            exampleDialogs: exampleDialogs,
            worldBookItems: worldBookItems,
            memoryItems: memoryItems,
            currentInput: currentInput,
            timeContext: timeContext,
            totalBudget: totalBudget
        )
    }

    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
        stageTurnPlan: StageTurnPlan?,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview {
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let systemPrompt = makeSystemPrompt(characterCard: characterCard)
        let characterDescription = buildCharacterDescription(characterCard)
        let scenario = makeScenario(conversation: conversation, characterCard: characterCard)
        let timeContext = makeTimeContext()
        let exampleDialogs = makeExampleDialogs(characterCard: characterCard)

        return preview(
            systemPrompt: systemPrompt,
            stageTurnPlan: stageTurnPlan,
            characterDescription: characterDescription,
            scenario: scenario,
            slowPlotMode: conversation.slowPlotMode,
            exampleDialogs: exampleDialogs,
            worldBookItems: BackgroundAssembler.worldBookItems(from: backgroundPacket),
            memoryItems: BackgroundAssembler.memoryItems(from: backgroundPacket),
            currentInput: currentInput,
            timeContext: timeContext,
            totalBudget: totalBudget
        )
    }

    static func preview(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> PromptAssemblyPreview {
        preview(
            conversation: conversation,
            characterCard: characterCard,
            backgroundPacket: backgroundPacket,
            stageTurnPlan: nil,
            currentInput: currentInput,
            endpoint: endpoint
        )
    }

    private static func preview(
        systemPrompt: String,
        stageTurnPlan: StageTurnPlan? = nil,
        characterDescription: String?,
        scenario: String?,
        slowPlotMode: Bool,
        exampleDialogs: [ChatMessage],
        worldBookItems: [BackgroundPromptItem],
        memoryItems: [BackgroundPromptItem],
        currentInput: String,
        timeContext: String,
        totalBudget: Int
    ) -> PromptAssemblyPreview {
        let stageIdentityMessage = stageTurnPlan.map { ChatMessage(role: "system", content: $0.stageIdentityPrompt) }
        let systemMessage = ChatMessage(role: "system", content: systemPrompt)
        let participantMessage = stageTurnPlan?.participantPrompt.map { ChatMessage(role: "system", content: $0) }
        let characterMessage = characterDescription.map { ChatMessage(role: "system", content: $0) }
        let scenarioMessage = scenario.map { ChatMessage(role: "system", content: $0) }
        let slowPlotMessage: ChatMessage? = slowPlotMode
            ? ChatMessage(role: "system", content: AppConstants.slowPlotModePrompt)
            : nil
        let stableIdentityMessages = [
            stageIdentityMessage,
            systemMessage,
            participantMessage,
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
        let worldBookTokens = worldBookItems.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent($1))) }
        let memoryTokens = memoryItems.reduce(0) { $0 + TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent($1))) }
        let exampleTokens = exampleDialogs.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let tokenBudget = TokenBudget.calculate(
            totalBudget: totalBudget,
            fixedTokens: fixedTokens,
            exampleDialogsTokens: exampleTokens,
            worldBookTokens: worldBookTokens,
            memoryTokens: memoryTokens
        )

        let trimmedExampleDialogs = trim(messages: exampleDialogs, within: tokenBudget.exampleDialogsBudget)
        let trimmedWorldBookItems = trim(worldBookItems: worldBookItems, within: tokenBudget.worldBookBudget)
        let trimmedMemoryItems = trim(memoryItems: memoryItems, within: tokenBudget.memoryBudget)

        let exampleDialogsBlock = makeExampleDialogsBlock(trimmedExampleDialogs)
        let worldBookBlock = makeWorldBookBlock(trimmedWorldBookItems)
        let memoryBlock = makeMemoryBlock(trimmedMemoryItems)
        let directorInstructionBlock = stageTurnPlan?.directorInstructionPrompt.map {
            ChatMessage(role: "system", content: $0)
        }
        let currentTurnContextMessages = [
            exampleDialogsBlock,
            worldBookBlock,
            memoryBlock,
            directorInstructionBlock,
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
            triggeredEntries: trimmedWorldBookItems.map(\.id)
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
        stageTurnPlan: StageTurnPlan? = nil,
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
            stageTurnPlan: stageTurnPlan,
            currentInput: currentInput,
            endpoint: endpoint
        )
        return assemble(processedHistory: processedHistory, context: context)
    }

    static func assembleWithPreselectedWorldBookEntries(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        worldBook: WorldBookRecord?,
        worldBookEntries: [WorldBookEntryRecord],
        memories: [MemoryEntryRecord] = [],
        processedHistory: [MessageRecord],
        stageTurnPlan: StageTurnPlan? = nil,
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult {
        let context = previewWithPreselectedWorldBookEntries(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            memories: memories,
            stageTurnPlan: stageTurnPlan,
            currentInput: currentInput,
            endpoint: endpoint
        )
        return assemble(processedHistory: processedHistory, context: context)
    }

    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
        stageTurnPlan: StageTurnPlan?,
        processedHistory: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult {
        let context = preview(
            conversation: conversation,
            characterCard: characterCard,
            backgroundPacket: backgroundPacket,
            stageTurnPlan: stageTurnPlan,
            currentInput: currentInput,
            endpoint: endpoint
        )
        return assemble(processedHistory: processedHistory, context: context)
    }

    static func assemble(
        conversation: ConversationRecord,
        characterCard: CharacterCardRecord?,
        backgroundPacket: BackgroundPacket,
        processedHistory: [MessageRecord],
        currentInput: String,
        endpoint: APIEndpointConfig
    ) -> AssemblyResult {
        assemble(
            conversation: conversation,
            characterCard: characterCard,
            backgroundPacket: backgroundPacket,
            stageTurnPlan: nil,
            processedHistory: processedHistory,
            currentInput: currentInput,
            endpoint: endpoint
        )
    }

    private static func assemble(
        processedHistory: [MessageRecord],
        context: PromptAssemblyPreview
    ) -> AssemblyResult {
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

    static func makeWorldBookMessageContent(_ item: BackgroundPromptItem) -> String {
        BackgroundAssembler.makeWorldBookMessageContent(item)
    }

    static func makeMemoryMessageContent(_ item: BackgroundPromptItem) -> String {
        BackgroundAssembler.makeMemoryMessageContent(item)
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

    private static func makeWorldBookBlock(_ items: [BackgroundPromptItem]) -> ChatMessage? {
        guard !items.isEmpty else { return nil }
        let body = items.map { makeWorldBookMessageContent($0) }.joined(separator: "\n\n")
        return ChatMessage(role: "system", content: "[World Book Entries]\n\(body)\n[/World Book Entries]")
    }

    private static func makeMemoryBlock(_ items: [BackgroundPromptItem]) -> ChatMessage? {
        guard !items.isEmpty else { return nil }
        let body = items.map { makeMemoryMessageContent($0) }.joined(separator: "\n\n")
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
        selectWorldBookEntries(
            worldBook: worldBook,
            entries: entries,
            contextText: contextText,
            selectionMode: .keywordTriggered
        )
    }

    private static func selectWorldBookEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        contextText: String,
        selectionMode: WorldBookSelectionMode
    ) -> [WorldBookEntryRecord] {
        guard worldBook?.isEnabled ?? false else { return [] }
        switch selectionMode {
        case .keywordTriggered:
            return KeywordMatcher.triggeredEntries(entries, contextText: contextText)
        case .preselected:
            return entries.filter(\.isEnabled)
        }
    }

    private static func makeExampleDialogs(characterCard: CharacterCardRecord?) -> [ChatMessage] {
        guard let characterCard else { return [] }
        return (try? characterCard.exampleDialogMessages()) ?? []
    }

    private static func makeContextText(recentMessages: [MessageRecord], currentInput: String) -> String {
        let recentText = recentMessages.suffix(5).map(\.content).joined(separator: "\n")
        return [recentText, currentInput].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func trim(worldBookItems: [BackgroundPromptItem], within budget: Int) -> [BackgroundPromptItem] {
        guard !worldBookItems.isEmpty else { return [] }
        var result: [BackgroundPromptItem] = []
        var used = 0
        for item in worldBookItems {
            let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeWorldBookMessageContent(item)))
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(item)
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

    private static func trim(memoryItems: [BackgroundPromptItem], within budget: Int) -> [BackgroundPromptItem] {
        guard !memoryItems.isEmpty else { return [] }
        var result: [BackgroundPromptItem] = []
        var used = 0
        for item in memoryItems {
            let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent(item)))
            guard used + tokens <= budget || result.isEmpty else { break }
            result.append(item)
            used += tokens
        }
        return result
    }
}

private enum WorldBookSelectionMode {
    case keywordTriggered
    case preselected
}
