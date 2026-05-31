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
        let stageContext = try await databaseManager.fetchStageContext(conversationId: conversation.id)
        let stageTurnPlan: StageTurnPlan?
        if let stageContext {
            let input = DirectorRuntimeInput(
                stageContext: stageContext,
                inputRole: stageInputRole,
                currentInput: prompt
            )
            stageTurnPlan = try await directorExecutor.execute(input)
        } else {
            stageTurnPlan = nil
        }
        let activeSpeakerCardId = stageTurnPlan?.participant?.characterCardId
        let resolvedCharacterCardId = activeSpeakerCardId ?? selectedCharacterCardID ?? conversation.characterCardId

        var userMessageRecord: MessageRecord?
        if persistUserMessage {
            let sortOrder = try await databaseManager.nextSortOrder(conversationId: conversation.id)
            var record = MessageRecord(
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
            record.stageId = stageTurnPlan?.stage.id
            record.speakerKind = MessageSpeakerKind.participant.rawValue
            record.speakerId = nil
            record.speakerName = String(localized: "You")
            try await databaseManager.saveMessage(record)
            messages.append(MessageDisplayItem(record: record))
            syncPrefillNextRole(afterAppendingRole: record.role)
            userMessageRecord = record
        }

        let characterCard = try await databaseManager.fetchCharacterCard(id: resolvedCharacterCardId)
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
        if let stageContext {
            let stageSpeakers = resolveStageResponders(from: stageContext.activeParticipants)
            if !stageSpeakers.isEmpty {
                try await generateStageResponses(
                    prompt: prompt,
                    endpoint: endpoint,
                    stageTurnPlan: stageTurnPlan,
                    speakers: stageSpeakers,
                    promptHistoryMessages: promptHistoryMessages,
                    userMessageRecord: userMessageRecord
                )
                return
            }
        }

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
                stageContext: stageTurnPlan.map(StageBackgroundContext.init(stageTurnPlan:)),
                currentInput: prompt,
                tokenBudget: max(Int((Double(endpoint.maxContextTokens) * 0.15).rounded(.down)), 1),
                memoryLimit: 10,
                worldBookLimit: 10
            )
            let backgroundPacket = try await backgroundManager.prepare(
                request: backgroundRequest,
                policy: BackgroundPolicy.compatibilityDefault(tokenBudget: backgroundRequest.tokenBudget)
            )
            backgroundDiagnostics = backgroundPacket.diagnostics
            preview = PromptAssembler.preview(
                conversation: conversation,
                characterCard: characterCard,
                backgroundPacket: backgroundPacket,
                stageTurnPlan: stageTurnPlan,
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
                stageTurnPlan: stageTurnPlan,
                processedHistory: history,
                currentInput: prompt,
                endpoint: endpoint
            )
        } else {
            backgroundDiagnostics = nil
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
                    stageTurnPlan: stageTurnPlan,
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
                    stageTurnPlan: stageTurnPlan,
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
                    stageTurnPlan: stageTurnPlan,
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
                    stageTurnPlan: stageTurnPlan,
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

        var assistantRecord = MessageRecord(
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
        assistantRecord.stageId = stageTurnPlan?.stage.id
        assistantRecord.speakerKind = stageTurnPlan?.participant.map { _ in MessageSpeakerKind.participant.rawValue }
        assistantRecord.speakerId = stageTurnPlan?.participant?.id
        assistantRecord.speakerName = stageTurnPlan?.participant?.displayName ?? characterCard?.name
        messages.append(MessageDisplayItem(record: assistantRecord))
        syncPrefillNextRole(afterAppendingRole: assistantRecord.role)

        isGenerating = true
        let capturedTokenUsage = assembly.tokenUsage
        streamTask = Task { [weak self] in
            guard let self else { return }
            let streamStart = ContinuousClock.now
            let accumulator = StreamingResponseAccumulator(
                messageID: assistantRecord.id,
                initialContentRenderRevision: messages.first(where: { $0.id == assistantRecord.id })?.contentRenderRevision ?? 0,
                initialReasoningRenderRevision: messages.first(where: { $0.id == assistantRecord.id })?.reasoningRenderRevision ?? 0
            )
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
                    if let snapshot = await accumulator.append(delta) {
                        applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
                    }
                    if delta.finishReason != nil {
                        break
                    }
                }
                if let snapshot = await accumulator.flush(force: true) {
                    applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
                }
                let final = await accumulator.finalSnapshot()

                let completedRecords = try await persistCompletedAssistantMessages(
                    assistantRecord: assistantRecord,
                    content: final.content,
                    reasoningContent: final.reasoningContent,
                    stageTurnPlan: stageTurnPlan
                )

                // Compute streaming stats
                let elapsed = ContinuousClock.now - streamStart
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let outputTokens = final.usage?.completionTokens ?? TokenCounter.count(final.content)
                let inputTokens = final.usage?.promptTokens ?? capturedTokenUsage.totalUsed
                let tps = elapsedSeconds > 0 ? Double(outputTokens) / elapsedSeconds : 0
                let remaining = capturedTokenUsage.totalBudget - inputTokens - outputTokens
                let remainingPercent = capturedTokenUsage.totalBudget > 0
                    ? Double(max(remaining, 0)) / Double(capturedTokenUsage.totalBudget)
                    : 1.0

                let stats = StreamingStats(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    reasoningTokens: final.usage?.reasoningTokens ?? 0,
                    tokensPerSecond: tps,
                    contextRemainingPercent: remainingPercent,
                    totalBudget: capturedTokenUsage.totalBudget
                )
                if let first = completedRecords.first {
                    setAssistantStats(stats, messageID: first.id)
                }

                // Keep the local record aligned with extraction boundary updates.
                if let refreshed = try await databaseManager.fetchConversation(id: conversation.id) {
                    conversation = refreshed
                }
            } catch {
                if let snapshot = await accumulator.flush(force: true) {
                    applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
                }
                let final = await accumulator.finalSnapshot()
                try? await persistOrRemovePartialAssistant(assistantRecord, final: final)
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

    private func applyStreamingSnapshot(_ snapshot: StreamingRenderSnapshot, messageID: String) {
        guard snapshot.messageID == messageID,
              let index = messages.firstIndex(where: { $0.id == messageID })
        else { return }
        messages[index].applyStreamingSnapshot(snapshot)
    }

    private func setAssistantStats(_ stats: StreamingStats, messageID: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].streamingStats = stats
    }

    private func generateStageResponses(
        prompt: String,
        endpoint: APIEndpointConfig,
        stageTurnPlan: StageTurnPlan?,
        speakers: [StageParticipantRecord],
        promptHistoryMessages: [MessageRecord],
        userMessageRecord: MessageRecord?
    ) async throws {
        var baseSortOrder = if let userMessageRecord {
            userMessageRecord.sortOrder + 1
        } else {
            try await databaseManager.nextSortOrder(conversationId: conversation.id)
        }

        isGenerating = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            var generatedRecords: [MessageRecord] = []
            defer {
                isGenerating = false
                streamTask = nil
            }

            do {
                for speaker in speakers {
                    let characterCard = try await databaseManager.fetchCharacterCard(id: speaker.characterCardId)
                    let assembly = try await prepareAssembly(
                        prompt: prompt,
                        endpoint: endpoint,
                        characterCard: characterCard,
                        stageTurnPlan: stageTurnPlan?.forSpeaker(speaker),
                        promptHistoryMessages: promptHistoryMessages,
                        stageContinuationRecords: generatedRecords
                    )
                    tokenUsage = assembly.tokenUsage

                    var assistantRecord = MessageRecord(
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
                    assistantRecord.stageId = stageTurnPlan?.stage.id
                    assistantRecord.speakerKind = MessageSpeakerKind.participant.rawValue
                    assistantRecord.speakerId = speaker.id
                    assistantRecord.speakerName = speaker.displayName
                    messages.append(MessageDisplayItem(record: assistantRecord))
                    syncPrefillNextRole(afterAppendingRole: assistantRecord.role)

                    let result = try await streamAssistantResponse(
                        assistantRecord: assistantRecord,
                        assembly: assembly,
                        endpoint: endpoint
                    )
                    let completedRecords = try await persistCompletedAssistantMessages(
                        assistantRecord: assistantRecord,
                        content: result.content,
                        reasoningContent: result.reasoningContent,
                        stageTurnPlan: stageTurnPlan?.forSpeaker(speaker)
                    )
                    if let first = completedRecords.first {
                        setAssistantStats(
                            makeStreamingStats(
                                usage: result.usage,
                                content: result.content,
                                tokenUsage: assembly.tokenUsage,
                                elapsedSeconds: result.elapsedSeconds
                            ),
                            messageID: first.id
                        )
                    }
                    generatedRecords.append(contentsOf: completedRecords)
                    baseSortOrder += max(completedRecords.count, 1)
                }

                if let refreshed = try await databaseManager.fetchConversation(id: conversation.id) {
                    conversation = refreshed
                }
            } catch {
                appState.present(error: error.localizedDescription)
            }
        }
    }

    private func prepareAssembly(
        prompt: String,
        endpoint: APIEndpointConfig,
        characterCard: CharacterCardRecord?,
        stageTurnPlan: StageTurnPlan?,
        promptHistoryMessages: [MessageRecord],
        stageContinuationRecords: [MessageRecord] = []
    ) async throws -> AssemblyResult {
        let worldBook = try await databaseManager.fetchWorldBook(id: characterCard?.worldBookId)
        let worldBookEntries = try await databaseManager.fetchWorldBookEntries(worldBookId: worldBook?.id)
        let recentMessages = promptHistoryMessages + stageContinuationRecords
        let stageContinuationTokens = stageContinuationRecords.reduce(0) { total, record in
            total + TokenCounter.count(
                message: record.stageHistoryChatMessage(activeSpeakerId: stageTurnPlan?.participant?.id)
            )
        }

        if let backgroundManager {
            await rebuildWorldBookEmbeddingsIfNeeded(worldBook: worldBook)
            let backgroundRequest = BackgroundRequest(
                conversation: conversation,
                characterCard: characterCard,
                worldBook: worldBook,
                worldBookEntries: worldBookEntries,
                recentMessages: recentMessages,
                stageContext: stageTurnPlan.map(StageBackgroundContext.init(stageTurnPlan:)),
                currentInput: prompt,
                tokenBudget: max(Int((Double(endpoint.maxContextTokens) * 0.15).rounded(.down)), 1),
                memoryLimit: 10,
                worldBookLimit: 10
            )
            let backgroundPacket = try await backgroundManager.prepare(
                request: backgroundRequest,
                policy: BackgroundPolicy.compatibilityDefault(tokenBudget: backgroundRequest.tokenBudget)
            )
            backgroundDiagnostics = backgroundPacket.diagnostics
            let preview = PromptAssembler.preview(
                conversation: conversation,
                characterCard: characterCard,
                backgroundPacket: backgroundPacket,
                stageTurnPlan: stageTurnPlan,
                currentInput: prompt,
                endpoint: endpoint
            )
            let history = try await contextManager.prepareHistory(
                messages: promptHistoryMessages,
                conversation: conversation,
                endpoint: endpoint,
                fixedTokens: preview.fixedTokens + stageContinuationTokens
            )
            return PromptAssembler.assemble(
                conversation: conversation,
                characterCard: characterCard,
                backgroundPacket: backgroundPacket,
                stageTurnPlan: stageTurnPlan,
                processedHistory: history,
                currentInput: prompt,
                endpoint: endpoint
            ).appendingStageContinuation(
                records: stageContinuationRecords,
                activeSpeakerId: stageTurnPlan?.participant?.id
            )
        }

        backgroundDiagnostics = nil
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
            recentMessages: recentMessages,
            currentInput: prompt
        )
        let preview: PromptAssemblyPreview
        if usesPreselectedWorldBookEntries {
            preview = PromptAssembler.previewWithPreselectedWorldBookEntries(
                conversation: conversation,
                characterCard: characterCard,
                worldBook: worldBook,
                worldBookEntries: recalledWorldBookEntries,
                memories: memories,
                stageTurnPlan: stageTurnPlan,
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
                recentMessages: recentMessages,
                stageTurnPlan: stageTurnPlan,
                currentInput: prompt,
                endpoint: endpoint
            )
        }

        let history = try await contextManager.prepareHistory(
            messages: promptHistoryMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: preview.fixedTokens + stageContinuationTokens
        )
        if usesPreselectedWorldBookEntries {
            return PromptAssembler.assembleWithPreselectedWorldBookEntries(
                conversation: conversation,
                characterCard: characterCard,
                worldBook: worldBook,
                worldBookEntries: recalledWorldBookEntries,
                memories: memories,
                processedHistory: history,
                stageTurnPlan: stageTurnPlan,
                currentInput: prompt,
                endpoint: endpoint
            ).appendingStageContinuation(
                records: stageContinuationRecords,
                activeSpeakerId: stageTurnPlan?.participant?.id
            )
        }
        return PromptAssembler.assemble(
            conversation: conversation,
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: recalledWorldBookEntries,
            memories: memories,
            recentMessages: recentMessages,
            processedHistory: history,
            stageTurnPlan: stageTurnPlan,
            currentInput: prompt,
            endpoint: endpoint
        ).appendingStageContinuation(
            records: stageContinuationRecords,
            activeSpeakerId: stageTurnPlan?.participant?.id
        )
    }

    private struct StreamedAssistantResult {
        let content: String
        let reasoningContent: String?
        let usage: StreamUsage?
        let elapsedSeconds: Double
    }

    private func streamAssistantResponse(
        assistantRecord: MessageRecord,
        assembly: AssemblyResult,
        endpoint: APIEndpointConfig
    ) async throws -> StreamedAssistantResult {
        let streamStart = ContinuousClock.now
        let accumulator = StreamingResponseAccumulator(
            messageID: assistantRecord.id,
            initialContentRenderRevision: messages.first(where: { $0.id == assistantRecord.id })?.contentRenderRevision ?? 0,
            initialReasoningRenderRevision: messages.first(where: { $0.id == assistantRecord.id })?.reasoningRenderRevision ?? 0
        )
        do {
            for try await delta in apiClient.streamMessage(
                messages: assembly.messages,
                endpoint: endpoint,
                parameters: currentParameters
            ) {
                if let snapshot = await accumulator.append(delta) {
                    applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
                }
                if delta.finishReason != nil {
                    break
                }
            }
            if let snapshot = await accumulator.flush(force: true) {
                applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
            }

            let final = await accumulator.finalSnapshot()
            let elapsed = ContinuousClock.now - streamStart
            let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return StreamedAssistantResult(
                content: final.content,
                reasoningContent: final.reasoningContent,
                usage: final.usage,
                elapsedSeconds: elapsedSeconds
            )
        } catch {
            if let snapshot = await accumulator.flush(force: true) {
                applyStreamingSnapshot(snapshot, messageID: assistantRecord.id)
            }
            let final = await accumulator.finalSnapshot()
            try? await persistOrRemovePartialAssistant(assistantRecord, final: final)
            throw error
        }
    }

    private func makeStreamingStats(
        usage: StreamUsage?,
        content: String,
        tokenUsage: TokenUsageReport,
        elapsedSeconds: Double
    ) -> StreamingStats {
        let outputTokens = usage?.completionTokens ?? TokenCounter.count(content)
        let inputTokens = usage?.promptTokens ?? tokenUsage.totalUsed
        let tps = elapsedSeconds > 0 ? Double(outputTokens) / elapsedSeconds : 0
        let remaining = tokenUsage.totalBudget - inputTokens - outputTokens
        let remainingPercent = tokenUsage.totalBudget > 0
            ? Double(max(remaining, 0)) / Double(tokenUsage.totalBudget)
            : 1.0
        return StreamingStats(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            reasoningTokens: usage?.reasoningTokens ?? 0,
            tokensPerSecond: tps,
            contextRemainingPercent: remainingPercent,
            totalBudget: tokenUsage.totalBudget
        )
    }

    private func persistCompletedAssistantMessages(
        assistantRecord: MessageRecord,
        content: String,
        reasoningContent: String?,
        stageTurnPlan: StageTurnPlan?
    ) async throws -> [MessageRecord] {
        let parser = StageSpeakerBlockParser()
        let blocks: [StageSpeakerBlock]
        if let stageTurnPlan {
            let participants = if stageTurnPlan.restrictParsedSpeakerToActive, let participant = stageTurnPlan.participant {
                [participant]
            } else {
                stageTurnPlan.participants
            }
            blocks = parser.parse(content, participants: participants)
        } else {
            blocks = []
        }
        guard blocks.count > 1 else {
            var completed = MessageRecord(
                id: assistantRecord.id,
                conversationId: assistantRecord.conversationId,
                role: assistantRecord.role,
                content: blocks.first?.content ?? content,
                tokenCount: TokenCounter.count(blocks.first?.content ?? content),
                isCompressed: assistantRecord.isCompressed,
                originalContent: assistantRecord.originalContent,
                sortOrder: assistantRecord.sortOrder,
                createdAt: assistantRecord.createdAt,
                reasoningContent: reasoningContent
            )
            if let participant = blocks.first?.participant {
                completed.stageId = assistantRecord.stageId
                completed.speakerKind = MessageSpeakerKind.participant.rawValue
                completed.speakerId = participant.id
                completed.speakerName = participant.displayName
            } else {
                completed.stageId = assistantRecord.stageId
                completed.speakerKind = assistantRecord.speakerKind
                completed.speakerId = assistantRecord.speakerId
                completed.speakerName = assistantRecord.speakerName
            }
            replaceDisplayMessage(id: assistantRecord.id, with: completed)
            try await databaseManager.saveMessage(completed)
            return [completed]
        }

        var records: [MessageRecord] = []
        for (offset, block) in blocks.enumerated() {
            var record = MessageRecord(
                id: offset == 0 ? assistantRecord.id : UUID().uuidString,
                conversationId: assistantRecord.conversationId,
                role: assistantRecord.role,
                content: block.content,
                tokenCount: TokenCounter.count(block.content),
                isCompressed: assistantRecord.isCompressed,
                originalContent: nil,
                sortOrder: assistantRecord.sortOrder + offset,
                createdAt: offset == 0 ? assistantRecord.createdAt : Date(),
                reasoningContent: offset == 0 ? reasoningContent : nil
            )
            record.stageId = assistantRecord.stageId
            record.speakerKind = MessageSpeakerKind.participant.rawValue
            record.speakerId = block.participant.id
            record.speakerName = block.participant.displayName
            records.append(record)
        }

        messages.removeAll { $0.id == assistantRecord.id }
        messages.append(contentsOf: records.map(MessageDisplayItem.init(record:)))
        messages.sort { $0.sortOrder < $1.sortOrder }
        syncPrefillNextRole()
        for record in records {
            try await databaseManager.saveMessage(record)
        }
        return records
    }

    private func replaceDisplayMessage(id: String, with record: MessageRecord) {
        let item = MessageDisplayItem(record: record)
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = item
        } else {
            messages.append(item)
            messages.sort { $0.sortOrder < $1.sortOrder }
        }
        syncPrefillNextRole()
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
        syncPrefillNextRole()
    }

    private func persistOrRemovePartialAssistant(_ assistantRecord: MessageRecord) async throws {
        let finalContent = messages.first(where: { $0.id == assistantRecord.id })?.content ?? ""
        let finalReasoning = messages.first(where: { $0.id == assistantRecord.id })?.reasoningContent
        try await persistOrRemovePartialAssistant(
            assistantRecord,
            final: StreamingFinalSnapshot(
                content: finalContent,
                reasoningContent: finalReasoning,
                usage: nil
            )
        )
    }

    private func persistOrRemovePartialAssistant(
        _ assistantRecord: MessageRecord,
        final: StreamingFinalSnapshot
    ) async throws {
        let finalContent = final.content
        let finalReasoning = final.reasoningContent
        guard !finalContent.isEmpty || !(finalReasoning?.isEmpty ?? true) else {
            removeAssistantPlaceholder(id: assistantRecord.id)
            return
        }

        var partial = MessageRecord(
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
        partial.stageId = assistantRecord.stageId
        partial.speakerKind = assistantRecord.speakerKind
        partial.speakerId = assistantRecord.speakerId
        partial.speakerName = assistantRecord.speakerName
        try await databaseManager.saveMessage(partial)
    }

    func saveDirectorInstruction(_ content: String) async throws {
        let stageContext: StageContext
        if let existing = try await databaseManager.fetchStageContext(conversationId: conversation.id) {
            stageContext = existing
        } else {
            let created = try await databaseManager.createStage(
                conversationId: conversation.id,
                title: conversation.title,
                directorMode: .userControlled
            )
            stageContext = StageContext(stage: created, participants: [], instructions: [])
        }

        let now = Date()
        let instruction = try StageInstruction.userDirected(
            id: UUID().uuidString,
            content: content,
            createdAt: now
        )
        let record = StageInstructionRecord(
            id: instruction.id,
            stageId: stageContext.stage.id,
            source: instruction.source.rawValue,
            content: instruction.content,
            visibility: instruction.visibility.rawValue,
            createdAt: instruction.createdAt
        )
        try await databaseManager.saveStageInstruction(record)
        await loadStage()
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

            await prepareIdleReflectDraftIfNeeded()
        }
    }

    private func prepareIdleReflectDraftIfNeeded() async {
        guard let worker = memoryReflectBackgroundWorker else { return }

        do {
            let endpoint = try await resolveEndpointConfig()
            let result = try await worker.prepareIdleDraft(
                characterCardId: selectedCharacterCardID ?? conversation.characterCardId,
                endpoint: endpoint
            )
            idleReflectDraft = result.observation
            idleReflectDiagnostics = result.diagnostics
            idleReflectSkippedReason = result.skippedReason
        } catch {
            logger.error("Idle memory reflect draft failed for conversation \(self.conversation.id): \(error.localizedDescription)")
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

private extension AssemblyResult {
    func appendingStageContinuation(
        records: [MessageRecord],
        activeSpeakerId: String?
    ) -> AssemblyResult {
        guard !records.isEmpty else { return self }
        var messages = messages
        let continuationMessages = records.map {
            $0.stageHistoryChatMessage(activeSpeakerId: activeSpeakerId)
        }
        messages.append(contentsOf: continuationMessages)
        let continuationTokens = records.reduce(0) { total, record in
            total + TokenCounter.count(message: record.stageHistoryChatMessage(activeSpeakerId: activeSpeakerId))
        }
        let totalUsed = tokenUsage.totalUsed + continuationTokens
        let usage = TokenUsageReport(
            totalBudget: tokenUsage.totalBudget,
            systemPrompt: tokenUsage.systemPrompt,
            characterDescription: tokenUsage.characterDescription,
            scenario: tokenUsage.scenario,
            slowPlotDirective: tokenUsage.slowPlotDirective,
            timeContext: tokenUsage.timeContext,
            background: tokenUsage.background,
            worldBookEntries: tokenUsage.worldBookEntries,
            memories: tokenUsage.memories,
            exampleDialogs: tokenUsage.exampleDialogs,
            history: tokenUsage.history + continuationTokens,
            currentInput: tokenUsage.currentInput,
            totalUsed: totalUsed,
            remaining: max(tokenUsage.totalBudget - totalUsed, 0)
        )
        return AssemblyResult(
            messages: messages,
            tokenUsage: usage,
            triggeredEntries: triggeredEntries
        )
    }
}

private extension MessageRecord {
    func stageHistoryChatMessage(activeSpeakerId: String?) -> ChatMessage {
        let trimmedSpeaker = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedSpeaker, !trimmedSpeaker.isEmpty else {
            return chatMessage
        }
        let promptRole = speakerId == activeSpeakerId ? role : "user"
        return ChatMessage(role: promptRole, content: "\(trimmedSpeaker): \(content)")
    }
}
