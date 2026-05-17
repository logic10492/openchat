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

        return try await makeEndpointConfig(endpoint: resolvedEndpoint, model: resolvedModel)
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

        // Pre-response memory extraction: extract before retrieval so new memories are immediately available
        if try await shouldExtractMemories(for: conversation),
           characterCard?.id != nil {
            extractionPhase = .extracting
            do {
                let result = try await memoryManager.extractMemories(from: conversation)
                if result.isEmpty {
                    extractionPhase = .skipped
                } else {
                    let summaries = result.map(\.content)
                    extractionPhase = .completed(count: result.count, summaries: summaries)
                    logger.info("Memory extraction completed: \(result.count) memories extracted for conversation \(self.conversation.id)")
                    // Refresh conversation record to pick up updated lastExtractedSortOrder
                    if let refreshed = try await databaseManager.fetchConversation(id: conversation.id) {
                        conversation = refreshed
                    }
                }
            } catch {
                extractionPhase = .failed(description: error.localizedDescription)
                logger.error("Memory extraction failed for conversation \(self.conversation.id): \(error.localizedDescription)")
            }
        }

        let currentMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let promptHistoryMessages = makePromptHistoryMessages(
            from: currentMessages,
            prompt: prompt,
            persistedUserMessage: userMessageRecord
        )

        let preview: PromptAssemblyPreview
        let assembly: AssemblyResult
        if let backgroundManager {
            await rebuildWorldBookEmbeddingsIfNeeded(worldBook: worldBook)
            let backgroundRequest = BackgroundRequest(
                conversation: conversation,
                characterCard: characterCard,
                worldBook: worldBook,
                worldBookEntries: worldBookEntries,
                recentMessages: promptHistoryMessages,
                currentInput: prompt,
                tokenBudget: max(Int((Double(endpoint.maxContextTokens) * 0.15).rounded(.down)), 1),
                memoryLimit: 10,
                worldBookLimit: 10
            )
            let backgroundPacket = try await backgroundManager.prepare(
                request: backgroundRequest,
                policy: BackgroundPolicy.compatibilityDefault(tokenBudget: backgroundRequest.tokenBudget)
            )
            preview = PromptAssembler.preview(
                conversation: conversation,
                characterCard: characterCard,
                backgroundPacket: backgroundPacket,
                currentInput: prompt,
                endpoint: endpoint
            )
            let history = try await contextManager.prepareHistory(
                messages: promptHistoryMessages,
                conversation: conversation,
                endpoint: endpoint,
                fixedTokens: preview.fixedTokens
            )
            assembly = PromptAssembler.assemble(
                conversation: conversation,
                characterCard: characterCard,
                backgroundPacket: backgroundPacket,
                processedHistory: history,
                currentInput: prompt,
                endpoint: endpoint
            )
        } else {
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

            let usesPreselectedWorldBookEntries = worldBookSource != nil
            let recalledWorldBookEntries = await recallWorldBookEntries(
                worldBook: worldBook,
                entries: worldBookEntries,
                recentMessages: promptHistoryMessages,
                currentInput: prompt
            )
            if usesPreselectedWorldBookEntries {
                preview = PromptAssembler.previewWithPreselectedWorldBookEntries(
                    conversation: conversation,
                    characterCard: characterCard,
                    worldBook: worldBook,
                    worldBookEntries: recalledWorldBookEntries,
                    memories: memories,
                    currentInput: prompt,
                    endpoint: endpoint
                )
            } else {
                preview = PromptAssembler.preview(
                    conversation: conversation,
                    characterCard: characterCard,
                    worldBook: worldBook,
                    worldBookEntries: recalledWorldBookEntries,
                    memories: memories,
                    recentMessages: promptHistoryMessages,
                    currentInput: prompt,
                    endpoint: endpoint
                )
            }

            let history = try await contextManager.prepareHistory(
                messages: promptHistoryMessages,
                conversation: conversation,
                endpoint: endpoint,
                fixedTokens: preview.fixedTokens
            )
            if usesPreselectedWorldBookEntries {
                assembly = PromptAssembler.assembleWithPreselectedWorldBookEntries(
                    conversation: conversation,
                    characterCard: characterCard,
                    worldBook: worldBook,
                    worldBookEntries: recalledWorldBookEntries,
                    memories: memories,
                    processedHistory: history,
                    currentInput: prompt,
                    endpoint: endpoint
                )
            } else {
                assembly = PromptAssembler.assemble(
                    conversation: conversation,
                    characterCard: characterCard,
                    worldBook: worldBook,
                    worldBookEntries: recalledWorldBookEntries,
                    memories: memories,
                    recentMessages: promptHistoryMessages,
                    processedHistory: history,
                    currentInput: prompt,
                    endpoint: endpoint
                )
            }
        }
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
            defer {
                isGenerating = false
                streamTask = nil
            }
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

                // Keep the local record aligned with extraction boundary updates.
                if let refreshed = try await databaseManager.fetchConversation(id: conversation.id) {
                    conversation = refreshed
                }
            } catch {
                try? await persistOrRemovePartialAssistant(assistantRecord)
                appState.present(error: error.localizedDescription)
            }
        }
    }

    private func makeEndpointConfig(
        endpoint: APIEndpointRecord,
        model: EndpointModelRecord
    ) async throws -> APIEndpointConfig {
        let storedKey = try apiKeyStore.readKey(endpointId: endpoint.id)
        if storedKey == nil, let legacyKey = endpoint.apiKey?.nilIfBlank {
            try apiKeyStore.saveKey(legacyKey, endpointId: endpoint.id)
            var sanitized = endpoint
            sanitized.apiKey = nil
            try await databaseManager.saveEndpoint(sanitized)
            return try APIEndpointConfig(from: sanitized, model: model, apiKey: legacyKey)
        }
        return try APIEndpointConfig(from: endpoint, model: model, apiKey: storedKey ?? endpoint.apiKey)
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

    private func shouldExtractMemories(for conversation: ConversationRecord) async throws -> Bool {
        let latestConversation = try await databaseManager.fetchConversation(id: conversation.id) ?? conversation
        let cutoff = latestConversation.lastExtractedSortOrder
        let records = try await databaseManager.fetchMessages(conversationId: latestConversation.id)
        let pendingCount = records.lazy.filter { record in
            guard let cutoff else { return true }
            return record.sortOrder > cutoff
        }.count
        return pendingCount >= Self.minimumPendingMessagesForExtraction
    }

    private func recallWorldBookEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String
    ) async -> [WorldBookEntryRecord] {
        guard let worldBookSource else {
            return entries
        }

        await rebuildWorldBookEmbeddingsIfNeeded(worldBook: worldBook)

        do {
            let result = try await worldBookSource.recallEntries(
                worldBook: worldBook,
                entries: entries,
                recentMessages: recentMessages,
                currentInput: currentInput,
                limit: 10
            )
            if result.trace.omissions.contains(where: { $0.reason == .semanticUnavailable }) {
                logger.warning("World book semantic recall unavailable; keyword recall fallback used")
            }
            return result.entries.map(\.entry)
        } catch {
            logger.warning("World book recall failed; falling back to prompt keyword path: \(error.localizedDescription)")
            guard worldBook?.isEnabled ?? false else { return [] }
            let contextText = [
                recentMessages.suffix(5).map(\.content).joined(separator: "\n"),
                currentInput,
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            return KeywordMatcher.triggeredEntries(entries, contextText: contextText)
        }
    }

    private func rebuildWorldBookEmbeddingsIfNeeded(worldBook: WorldBookRecord?) async {
        guard let worldBookId = worldBook?.id, let worldBookEmbeddingIndexer else {
            return
        }

        do {
            let result = try await worldBookEmbeddingIndexer.rebuildMissingOrStale(
                worldBookId: worldBookId,
                limit: 8
            )
            if !result.failed.isEmpty {
                logger.warning("World book bounded rebuild had \(result.failed.count) failed entries for world book \(worldBookId)")
            }
        } catch {
            logger.warning("World book bounded rebuild failed for world book \(worldBookId): \(error.localizedDescription)")
        }
    }

    private func removeAssistantPlaceholder(id: String) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    private func persistOrRemovePartialAssistant(_ assistantRecord: MessageRecord) async throws {
        let finalContent = messages.first(where: { $0.id == assistantRecord.id })?.content ?? ""
        let finalReasoning = messages.first(where: { $0.id == assistantRecord.id })?.reasoningContent
        guard !finalContent.isEmpty || !(finalReasoning?.isEmpty ?? true) else {
            removeAssistantPlaceholder(id: assistantRecord.id)
            return
        }

        let partial = MessageRecord(
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
        try await databaseManager.saveMessage(partial)
    }

    func triggerMemoryExtraction() {
        Task {
            do {
                let result = try await memoryManager.extractMemories(from: conversation)
                if !result.isEmpty {
                    logger.info("Memory extraction on disappear completed: \(result.count) memories for conversation \(self.conversation.id)")
                }
            } catch {
                logger.error("Memory extraction on disappear failed for conversation \(self.conversation.id): \(error.localizedDescription)")
            }
        }
    }

    func dismissExtractionIndicator() {
        guard extractionPhase != .extracting else { return }
        extractionPhase = .idle
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
