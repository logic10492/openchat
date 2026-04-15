import Foundation

extension ChatViewModel {
    func generateResponse(
        for prompt: String,
        persistUserMessage: Bool
    ) async throws {
        let storedEndpoint = try await databaseManager.fetchEndpoint(id: selectedEndpointID ?? conversation.apiEndpointId)
        let endpointRecord = if let storedEndpoint {
            storedEndpoint
        } else {
            try await databaseManager.fetchDefaultEndpoint()
        }

        guard let resolvedEndpoint = endpointRecord else {
            throw APIError.noEndpointConfigured
        }

        let endpoint = try APIEndpointConfig(from: resolvedEndpoint)

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

        var memories: [MemoryEntryRecord] = []
        if let characterCardId = characterCard?.id {
            memories = (try? await memoryManager.retrieveMemories(
                for: characterCardId,
                query: prompt,
                limit: 10
            )) ?? []
        }

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            memories: memories,
            recentMessages: currentMessages,
            currentInput: prompt,
            endpoint: endpoint
        )

        let history = try await contextManager.prepareHistory(
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
            recentMessages: currentMessages,
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
            createdAt: .now
        )
        messages.append(MessageDisplayItem(record: assistantRecord))

        isGenerating = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in apiClient.streamMessage(
                    messages: assembly.messages,
                    endpoint: endpoint,
                    parameters: currentParameters
                ) {
                    if !delta.content.isEmpty {
                        appendAssistantDelta(delta.content, messageID: assistantRecord.id)
                    }
                    if delta.finishReason != nil {
                        break
                    }
                }

                let finalContent = messages.first(where: { $0.id == assistantRecord.id })?.content ?? ""
                let completed = MessageRecord(
                    id: assistantRecord.id,
                    conversationId: assistantRecord.conversationId,
                    role: assistantRecord.role,
                    content: finalContent,
                    tokenCount: TokenCounter.count(finalContent),
                    isCompressed: assistantRecord.isCompressed,
                    originalContent: assistantRecord.originalContent,
                    sortOrder: assistantRecord.sortOrder,
                    createdAt: assistantRecord.createdAt
                )
                try await databaseManager.saveMessage(completed)
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

    private func removeAssistantPlaceholder(id: String) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    func triggerMemoryExtraction() {
        Task {
            try? await memoryManager.extractMemories(from: conversation)
        }
    }
}
