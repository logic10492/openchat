import Foundation
import os.log

private let logger = Logger(subsystem: "com.openchat", category: "ChatGeneration")

extension ChatViewModel {
    func resolveEndpointConfig() async throws -> APIEndpointConfig {
        let storedEndpoint = try await databaseManager.fetchEndpoint(id: selectedEndpointID ?? conversation.apiEndpointId)
        let endpointRecord = if let storedEndpoint {
            storedEndpoint
        } else {
            try await databaseManager.fetchDefaultEndpoint()
        }

        guard let resolvedEndpoint = endpointRecord else {
            throw APIError.noEndpointConfigured
        }

        let resolvedModelName = selectedModelName ?? conversation.modelName
        let resolvedModel: EndpointModelRecord
        if let modelName = resolvedModelName,
           let model = try await databaseManager.fetchEndpointModel(endpointId: resolvedEndpoint.id, modelId: modelName) {
            resolvedModel = model
        } else if let defaultModel = try await databaseManager.fetchDefaultModel(endpointId: resolvedEndpoint.id) {
            resolvedModel = defaultModel
        } else {
            resolvedModel = EndpointModelRecord(
                id: UUID().uuidString,
                endpointId: resolvedEndpoint.id,
                modelId: resolvedModelName ?? "default",
                maxContextTokens: AppConstants.defaultMaxContextTokens,
                apiMode: APIMode.chatCompletions.rawValue,
                providerDialect: APIProviderDialect.openAICompatible.rawValue,
                isDefault: true,
                isManual: true,
                createdAt: .now
            )
        }

        return try APIEndpointConfig(from: resolvedEndpoint, model: resolvedModel)
    }

    func generateResponse(
        for prompt: String,
        persistUserMessage: Bool
    ) async throws {
        let endpoint = try await resolveEndpointConfig()

        var userMessageRecord: MessageRecord?
        if persistUserMessage {
            let sortOrder = try await databaseManager.nextSortOrder(conversationId: conversation.id)
            let record = MessageRecord(
                id: UUID().uuidString,
                conversationId: conversation.id,
                role: "user",
                content: prompt,
                tokenCount: TokenCounter.count(prompt),
                isCompressed: false,
                originalContent: nil,
                sortOrder: sortOrder,
                createdAt: .now
            )
            try await databaseManager.saveMessage(record)
            messages.append(MessageDisplayItem(record: record))
            userMessageRecord = record
        }

        let characterCard = try await databaseManager.fetchCharacterCard(id: selectedCharacterCardID ?? conversation.characterCardId)
        let worldBook = try await databaseManager.fetchWorldBook(id: characterCard?.worldBookId)
        let worldBookEntries = try await databaseManager.fetchWorldBookEntries(worldBookId: worldBook?.id)
        let currentMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let promptHistoryMessages = makePromptHistoryMessages(
            from: currentMessages,
            prompt: prompt,
            persistedUserMessage: userMessageRecord
        )

        var memories: [MemoryEntryRecord] = []
        if let characterCardId = characterCard?.id {
            do {
                memories = try await memoryManager.retrieveMemories(
                    for: characterCardId,
                    query: prompt,
                    limit: 10
                )
            } catch {
                logger.warning("Memory retrieval failed after fallback for character \(characterCardId): \(error.localizedDescription)")
            }
        }

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            memories: memories,
            recentMessages: promptHistoryMessages,
            currentInput: prompt,
            endpoint: endpoint
        )

        let history = try await contextManager.prepareHistory(
            messages: promptHistoryMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: preview.fixedTokens
        )

        let assembly = PromptAssembler.assemble(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            memories: memories,
            recentMessages: promptHistoryMessages,
            processedHistory: history,
            currentInput: prompt,
            endpoint: endpoint
        )
        tokenUsage = assembly.tokenUsage

        let baseSortOrder: Int
        if let userMessageRecord {
            baseSortOrder = userMessageRecord.sortOrder + 1
        } else {
            baseSortOrder = try await databaseManager.nextSortOrder(conversationId: conversation.id)
        }

        let assistantRecord = MessageRecord(
            id: UUID().uuidString,
            conversationId: conversation.id,
            role: "assistant",
            content: "",
            tokenCount: nil,
            isCompressed: false,
            originalContent: nil,
            sortOrder: baseSortOrder,
            createdAt: .now,
            reasoningContent: nil
        )
        messages.append(MessageDisplayItem(record: assistantRecord))

        isGenerating = true
        let capturedTokenUsage = assembly.tokenUsage
        streamTask = Task { [weak self] in
            guard let self else { return }
            var lastUsage: StreamUsage?
            let streamStart = ContinuousClock.now
            do {
                for try await delta in apiClient.streamMessage(
                    messages: assembly.messages,
                    endpoint: endpoint,
                    parameters: currentParameters
                ) {
                    if !delta.content.isEmpty {
                        appendAssistantDelta(delta.content, messageID: assistantRecord.id)
                    }
                    if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                        appendReasoningDelta(reasoning, messageID: assistantRecord.id)
                    }
                    if let usage = delta.usage {
                        lastUsage = usage
                    }
                    if delta.finishReason != nil {
                        break
                    }
                }

                let finalContent = messages.first(where: { $0.id == assistantRecord.id })?.content ?? ""
                let finalReasoning = messages.first(where: { $0.id == assistantRecord.id })?.reasoningContent
                let completed = MessageRecord(
                    id: assistantRecord.id,
                    conversationId: assistantRecord.conversationId,
                    role: assistantRecord.role,
                    content: finalContent,
                    tokenCount: TokenCounter.count(finalContent),
                    isCompressed: assistantRecord.isCompressed,
                    originalContent: assistantRecord.originalContent,
                    sortOrder: assistantRecord.sortOrder,
                    createdAt: assistantRecord.createdAt,
                    reasoningContent: finalReasoning
                )
                try await databaseManager.saveMessage(completed)

                // Compute streaming stats
                let elapsed = ContinuousClock.now - streamStart
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let outputTokens = lastUsage?.completionTokens ?? TokenCounter.count(finalContent)
                let inputTokens = lastUsage?.promptTokens ?? capturedTokenUsage.totalUsed
                let tps = elapsedSeconds > 0 ? Double(outputTokens) / elapsedSeconds : 0
                let remaining = capturedTokenUsage.totalBudget - inputTokens - outputTokens
                let remainingPercent = capturedTokenUsage.totalBudget > 0
                    ? Double(max(remaining, 0)) / Double(capturedTokenUsage.totalBudget)
                    : 1.0

                let stats = StreamingStats(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    reasoningTokens: lastUsage?.reasoningTokens ?? 0,
                    tokensPerSecond: tps,
                    contextRemainingPercent: remainingPercent,
                    totalBudget: capturedTokenUsage.totalBudget
                )
                setAssistantStats(stats, messageID: assistantRecord.id)

                // Periodic memory extraction
                messagesSinceLastExtraction += 2 // user + assistant
                if messagesSinceLastExtraction >= Self.extractionInterval {
                    messagesSinceLastExtraction = 0
                    triggerMemoryExtraction()
                }
            } catch {
                removeAssistantPlaceholder(id: assistantRecord.id)
                appState.present(error: error.localizedDescription)
            }

            isGenerating = false
            streamTask = nil
        }
    }

    private func appendAssistantDelta(_ delta: String, messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].content += delta
    }

    private func appendReasoningDelta(_ delta: String, messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].reasoningContent = (messages[index].reasoningContent ?? "") + delta
    }

    private func setAssistantStats(_ stats: StreamingStats, messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].streamingStats = stats
    }

    private func removeAssistantPlaceholder(id: String) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    func triggerMemoryExtraction() {
        Task {
            do {
                let result = try await memoryManager.extractMemories(from: conversation)
                if !result.isEmpty {
                    logger.info("Memory extraction completed: \(result.count) memories extracted for conversation \(self.conversation.id)")
                    let summary = result.map { "· \($0.content)" }.joined(separator: "\n")
                    let text = String(localized: "🧠 Memorized \(result.count) entries") + "\n" + summary
                    await MainActor.run {
                        self.messages.append(.memoryMarker(content: text))
                    }
                }
            } catch {
                logger.error("Memory extraction failed for conversation \(self.conversation.id): \(error.localizedDescription)")
                let text = String(localized: "🧠 Memory extraction failed") + "\n" + error.localizedDescription
                await MainActor.run {
                    self.messages.append(.memoryMarker(content: text, isError: true))
                }
            }
        }
    }

    private func makePromptHistoryMessages(
        from messages: [MessageRecord],
        prompt: String,
        persistedUserMessage: MessageRecord?
    ) -> [MessageRecord] {
        if let persistedUserMessage {
            return messages.filter { $0.id != persistedUserMessage.id }
        }

        guard let currentInputRecord = messages.last(where: {
            $0.role == "user" && $0.content == prompt
        }) else {
            return messages
        }
        return messages.filter { $0.id != currentInputRecord.id }
    }
}
