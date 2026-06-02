import Foundation
import Observation
import os

@MainActor
@Observable
final class ChatViewModel {
    let databaseManager: DatabaseManager
    let apiClient: APIClient
    let contextManager: ContextManager
    let memoryManager: MemoryManager
    let memoryReflectBackgroundWorker: MemoryReflectBackgroundWorker?
    let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer?
    let worldBookSource: WorldBookSource?
    let backgroundManager: BackgroundManager?
    let titleGenerator: TitleGenerator
    let apiKeyStore: any APIKeyStore
    let appState: AppState
    let skillBundleMaterializer: (any CharacterSkillBundleMaterializing)?
    @ObservationIgnored
    let directorExecutor: any DirectorExecuting
    @ObservationIgnored
    let directorAgentExecutor: any AgentExecutor

    var conversation: ConversationRecord
    var messages: [MessageDisplayItem] = []
    var hasEarlierMessages = false
    var isLoadingEarlierMessages = false
    var isGenerating = false
    var isGeneratingTitle = false
    var extractionPhase: MemoryExtractionPhase = .idle
    var tokenUsage: TokenUsageReport?
    var backgroundDiagnostics: BackgroundDiagnostics?
    var idleReflectDraft: MemoryReflectObservation?
    var idleReflectDiagnostics: MemoryReflectDiagnostics?
    var idleReflectSkippedReason: MemoryReflectBackgroundSkipReason?
    private(set) var availableEndpoints: [APIEndpointRecord] = []
    private(set) var availableCharacterCards: [CharacterCardRecord] = []
    private(set) var availableWorldBooks: [WorldBookRecord] = []
    private(set) var availableModelsForEndpoint: [EndpointModelRecord] = []
    private(set) var stage: StageRecord?
    private(set) var stageParticipants: [StageParticipantRecord] = []
    private(set) var stageInstructions: [StageInstructionRecord] = []

    var inputText = ""
    var isPrefillModeEnabled = false
    var stageInputRole: StageInputRole = .participant
    var stageResponderIds: [String] = []
    private var isStageResponderSelectionCustomized = false
    var conversationTitle: String
    var selectedEndpointID: String?
    var selectedModelName: String?
    var selectedCharacterCardID: String?
    var selectedContextStrategy: ContextStrategy
    var selectedCompressionMode: CompressionMode
    var customScenario = ""
    var slowPlotMode: Bool
    var usesCustomModelParameters = false
    var modelTemperature: Double
    var modelTopP: Double
    var modelMaxTokens: Int
    var thinkingEnabled = false
    var thinkingBudget = 8192
    var reasoningEffort: ReasoningEffort = .high
    var showDetailedStats: Bool

    var selectedCharacterName: String? {
        guard let id = selectedCharacterCardID else { return nil }
        return availableCharacterCards.first(where: { $0.id == id })?.name
    }

    var selectedCharacterWorldBookName: String? {
        guard let id = selectedCharacterCardID,
              let card = availableCharacterCards.first(where: { $0.id == id }),
              let worldBookId = card.worldBookId else { return nil }
        return availableWorldBooks.first(where: { $0.id == worldBookId })?.name
    }

    var prefillNextRole: PrefillInputRole = .userMessage

    var showsConversationCharacterPicker: Bool {
        !isStageEnabled
    }

    var isStageEnabled: Bool {
        stage?.isEnabled == true
    }

    var directorMode: DirectorMode {
        get { stage?.directorModeValue ?? .silent }
        set {
            guard var stage else { return }
            stage.directorMode = newValue.rawValue
            stage.updatedAt = .now
            self.stage = stage
        }
    }

    var activeStageSpeakerName: String? {
        activeStageParticipants.first?.displayName
    }

    var activeStageParticipants: [StageParticipantRecord] {
        stageParticipants
            .filter { $0.isActive && $0.visibilityValue == .present }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @ObservationIgnored
    var streamTask: Task<Void, Never>?
    static let minimumPendingMessagesForExtraction = MemoryManager.minimumMessagesForExtraction
    private static let initialTimelineWindowSize = 120
    private static let earlierTimelinePageSize = 80

    init(
        conversation: ConversationRecord,
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        contextManager: ContextManager,
        memoryManager: MemoryManager,
        memoryReflectBackgroundWorker: MemoryReflectBackgroundWorker? = nil,
        worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer? = nil,
        worldBookSource: WorldBookSource? = nil,
        backgroundManager: BackgroundManager? = nil,
        titleGenerator: TitleGenerator,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        skillBundleMaterializer: (any CharacterSkillBundleMaterializing)? = nil,
        directorExecutor: any DirectorExecuting = DeterministicDirectorExecutor(),
        directorAgentExecutor: any AgentExecutor = LLMAgentExecutor(),
        appState: AppState
    ) {
        self.conversation = conversation
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.contextManager = contextManager
        self.memoryManager = memoryManager
        self.memoryReflectBackgroundWorker = memoryReflectBackgroundWorker
        self.worldBookEmbeddingIndexer = worldBookEmbeddingIndexer
        self.worldBookSource = worldBookSource
        self.backgroundManager = backgroundManager
        self.titleGenerator = titleGenerator
        self.apiKeyStore = apiKeyStore
        self.skillBundleMaterializer = skillBundleMaterializer
        self.directorExecutor = directorExecutor
        self.directorAgentExecutor = directorAgentExecutor
        self.appState = appState
        let defaultParameters = UserDefaults.standard.openChatDefaultModelParameters()
        conversationTitle = conversation.title
        selectedEndpointID = conversation.apiEndpointId
        selectedModelName = conversation.modelName
        selectedCharacterCardID = conversation.characterCardId
        selectedContextStrategy = ContextStrategy(rawValue: conversation.contextStrategy) ?? .truncation
        selectedCompressionMode = conversation.compressionModeValue
        customScenario = conversation.customScenario ?? ""
        slowPlotMode = conversation.slowPlotMode
        showDetailedStats = UserDefaults.standard.bool(forKey: "show_detailed_stats")
        modelTemperature = defaultParameters.temperature
        modelTopP = defaultParameters.topP
        modelMaxTokens = defaultParameters.maxTokens ?? 1024

        if let parameters = conversation.decodedModelParameters,
           !parameters.isLegacyImplicitConversationDefault {
            usesCustomModelParameters = true
            modelTemperature = parameters.temperature
            modelTopP = parameters.topP
            modelMaxTokens = parameters.maxTokens ?? 1024
            thinkingEnabled = parameters.isThinkingEnabled
            thinkingBudget = parameters.thinkingBudget ?? 8192
            reasoningEffort = parameters.reasoningEffort
        }
    }

    func loadMessages() async {
        do {
            let records = try await databaseManager.fetchRecentMessages(
                conversationId: conversation.id,
                limit: Self.initialTimelineWindowSize + 1
            )
            let visibleRecords = records.suffix(Self.initialTimelineWindowSize)
            messages = visibleRecords.map(MessageDisplayItem.init(record:))
            hasEarlierMessages = records.count > Self.initialTimelineWindowSize
            syncPrefillNextRole()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func loadEarlierMessagesIfNeeded() async {
        guard !isLoadingEarlierMessages, hasEarlierMessages else { return }
        guard let firstSortOrder = messages.first?.sortOrder else {
            hasEarlierMessages = false
            return
        }

        isLoadingEarlierMessages = true
        defer { isLoadingEarlierMessages = false }

        do {
            let records = try await databaseManager.fetchMessages(
                conversationId: conversation.id,
                beforeSortOrder: firstSortOrder,
                limit: Self.earlierTimelinePageSize + 1
            )
            let visibleRecords = records.suffix(Self.earlierTimelinePageSize)
            hasEarlierMessages = records.count > Self.earlierTimelinePageSize
            guard !visibleRecords.isEmpty else { return }
            let existingIDs = Set(messages.map(\.id))
            let olderItems = visibleRecords
                .filter { !existingIDs.contains($0.id) }
                .map(MessageDisplayItem.init(record:))
            messages.insert(contentsOf: olderItems, at: 0)
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func loadSettingsOptions() async {
        async let endpoints = databaseManager.fetchEndpoints()
        async let characterCards = databaseManager.fetchCharacterCards()
        async let worldBooks = databaseManager.fetchWorldBooks()

        do {
            availableEndpoints = try await endpoints
            availableCharacterCards = try await characterCards
            availableWorldBooks = try await worldBooks
            await loadModelsForEndpoint()
            await loadStage()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func loadStage() async {
        do {
            if let context = try await databaseManager.fetchStageContext(conversationId: conversation.id) {
                stage = context.stage
                stageParticipants = context.participants
                stageInstructions = context.instructions
                syncStageResponderSelection()
            } else {
                stage = nil
                stageParticipants = []
                stageInstructions = []
                stageResponderIds = []
            }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func resolveStageResponders(from activeParticipants: [StageParticipantRecord]) -> [StageParticipantRecord] {
        let resolvedIds = normalizedStageResponderIds(for: activeParticipants)
        if stageResponderIds != resolvedIds {
            stageResponderIds = resolvedIds
        }
        return resolvedIds.compactMap { id in
            activeParticipants.first { $0.id == id }
        }
    }

    private func normalizedStageResponderIds(for activeParticipants: [StageParticipantRecord]) -> [String] {
        let activeIds = Set(activeParticipants.map(\.id))
        var seen = Set<String>()
        let selected = stageResponderIds.filter { id in
            activeIds.contains(id) && seen.insert(id).inserted
        }
        if isStageResponderSelectionCustomized, !selected.isEmpty {
            return selected
        }
        if isStageResponderSelectionCustomized {
            isStageResponderSelectionCustomized = false
        }
        return activeParticipants.map(\.id)
    }

    private func syncStageResponderSelection() {
        stageResponderIds = normalizedStageResponderIds(for: activeStageParticipants)
    }

    func markStageResponderSelectionCustomized() {
        isStageResponderSelectionCustomized = true
    }

    func loadModelsForEndpoint() async {
        let endpointId = selectedEndpointID ?? conversation.apiEndpointId
        guard let endpointId else {
            // Try default endpoint
            if let defaultEndpoint = try? await databaseManager.fetchDefaultEndpoint() {
                availableModelsForEndpoint = (try? await databaseManager.fetchEndpointModels(endpointId: defaultEndpoint.id)) ?? []
            } else {
                availableModelsForEndpoint = []
            }
            return
        }
        availableModelsForEndpoint = (try? await databaseManager.fetchEndpointModels(endpointId: endpointId)) ?? []
    }

    func sendMessage() async {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !isGenerating else { return }

        do {
            if isPrefillModeEnabled, !isStageEnabled {
                try await savePrefilledMessage(trimmedInput)
                inputText = ""
                return
            }
            if stageInputRole.isDirectorInstructionInput {
                try await saveDirectorInstruction(trimmedInput)
                inputText = ""
                return
            }
            // Generate title first if this is a fresh conversation
            if !conversation.isTitleGenerated {
                await generateTitleIfNeeded(userMessage: trimmedInput)
            }
            try await generateResponse(for: trimmedInput, persistUserMessage: true)
            inputText = ""
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    private func savePrefilledMessage(_ content: String) async throws {
        let role = nextPrefillRole
        let characterCard: CharacterCardRecord?
        if role == "assistant" {
            characterCard = try await databaseManager.fetchCharacterCard(
                id: selectedCharacterCardID ?? conversation.characterCardId
            )
        } else {
            characterCard = nil
        }
        let sortOrder = try await databaseManager.nextSortOrder(conversationId: conversation.id)
        var record = MessageRecord(
            id: UUID().uuidString,
            conversationId: conversation.id,
            role: role,
            content: content,
            tokenCount: TokenCounter.count(content),
            isCompressed: false,
            originalContent: nil,
            sortOrder: sortOrder,
            createdAt: .now,
            reasoningContent: nil
        )
        record.speakerName = characterCard?.name
        try await databaseManager.saveMessage(record)
        messages.append(MessageDisplayItem(record: record))
        syncPrefillNextRole(afterAppendingRole: record.role)
        if let refreshed = try await databaseManager.fetchConversation(id: conversation.id) {
            conversation = refreshed
        }
    }

    private var nextPrefillRole: String {
        prefillNextRole == .assistantReply ? "assistant" : "user"
    }

    func renameConversation(newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        conversationTitle = trimmed
        conversation.isTitleGenerated = true
        conversation.updatedAt = .now
        do {
            try await databaseManager.saveConversation(conversation)
            appState.conversationListNeedsRefresh = true
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    private func generateTitleIfNeeded(userMessage: String) async {
        isGeneratingTitle = true
        defer { isGeneratingTitle = false }

        do {
            let endpoint = try await resolveEndpointConfig()

            let characterCard = try await databaseManager.fetchCharacterCard(
                id: selectedCharacterCardID ?? conversation.characterCardId
            )

            let scenario = conversation.customScenario?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? characterCard?.scenario?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

            let title = try await titleGenerator.generateTitle(
                scenario: scenario,
                characterCard: characterCard,
                userMessage: userMessage,
                endpoint: endpoint,
                parameters: currentParameters
            )

            conversation.title = title
            conversationTitle = title
            conversation.isTitleGenerated = true
            conversation.updatedAt = .now
            try await databaseManager.saveConversation(conversation)
            appState.conversationListNeedsRefresh = true
        } catch {
            // Title generation failure is non-blocking — keep the default title
            os.Logger(subsystem: "com.openchat", category: "TitleGenerator")
                .warning("Title generation failed, keeping default: \(error.localizedDescription)")
        }
    }

    func stopGenerating() {
        streamTask?.cancel()
    }

    func regenerateLastResponse() async {
        guard let lastUserMessage = messages.last(where: { $0.role == "user" }) else { return }
        if let lastAssistantMessage = messages.last(where: { $0.role == "assistant" }) {
            await deleteMessage(lastAssistantMessage.id)
        }

        do {
            try await generateResponse(for: lastUserMessage.content, persistUserMessage: false)
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func editMessage(_ messageId: String, newContent: String) async {
        let trimmedContent = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty, !isGenerating else { return }

        do {
            let records = try await databaseManager.fetchMessages(conversationId: conversation.id)
            guard var target = records.first(where: { $0.id == messageId }) else { return }
            guard target.role == "user" else { return }
            target.content = trimmedContent
            target.tokenCount = TokenCounter.count(trimmedContent)
            try await databaseManager.saveMessage(target)
            try await databaseManager.deleteCompressionCheckpoints(
                conversationId: conversation.id,
                sourceEndAtOrAfter: target.sortOrder
            )
            try await databaseManager.deleteMessages(
                conversationId: conversation.id,
                afterSortOrder: target.sortOrder
            )
            replaceTimelineMessage(with: target)
            removeTimelineMessages(afterSortOrder: target.sortOrder)
            try await generateResponse(for: trimmedContent, persistUserMessage: false)
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func deleteMessage(_ messageId: String) async {
        do {
            let records = try await databaseManager.fetchMessages(conversationId: conversation.id)
            let deletedSortOrder = records.first(where: { $0.id == messageId })?.sortOrder
            if let deletedSortOrder {
                try await databaseManager.deleteCompressionCheckpoints(
                    conversationId: conversation.id,
                    sourceEndAtOrAfter: deletedSortOrder
                )
            }
            try await databaseManager.deleteMessage(id: messageId)
            removeTimelineMessage(id: messageId)
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func saveConversationSettings() async {
        let trimmedTitle = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, trimmedTitle != conversation.title {
            conversation.title = trimmedTitle
            conversationTitle = trimmedTitle
            conversation.isTitleGenerated = true
            appState.conversationListNeedsRefresh = true
        }
        conversation.apiEndpointId = selectedEndpointID
        conversation.modelName = selectedModelName
        if showsConversationCharacterPicker {
            conversation.characterCardId = selectedCharacterCardID
        }
        conversation.contextStrategy = selectedContextStrategy.rawValue
        conversation.compressionMode = selectedCompressionMode.rawValue
        conversation.customScenario = customScenario.nilIfBlank
        conversation.slowPlotMode = slowPlotMode
        conversation.modelParameters = usesCustomModelParameters
            ? RecordCoders.encode(customModelParameters)
            : nil
        conversation.updatedAt = .now

        do {
            try await databaseManager.saveConversation(conversation)
            if let stage {
                try await databaseManager.setStageDirectorMode(stageId: stage.id, mode: stage.directorModeValue)
            }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func enableStage() async {
        do {
            let resolvedStage = if let stage {
                stage
            } else {
                try await databaseManager.createStage(
                    conversationId: conversation.id,
                    title: conversation.title,
                    directorMode: .silent
                )
            }
            stage = resolvedStage
            if let selectedCharacterCardID,
               let card = availableCharacterCards.first(where: { $0.id == selectedCharacterCardID }) {
                _ = try await databaseManager.addStageParticipant(
                    stageId: resolvedStage.id,
                    characterCard: card
                )
            }
            await loadStage()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func setDirectorMode(_ mode: DirectorMode) async {
        guard let stage else { return }
        do {
            try await databaseManager.setStageDirectorMode(stageId: stage.id, mode: mode)
            await loadStage()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func addStageParticipant(characterCardId: String) async {
        do {
            if stage == nil {
                await enableStage()
            }
            guard let stage,
                  let card = availableCharacterCards.first(where: { $0.id == characterCardId })
            else { return }
            _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: card)
            await loadStage()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func removeStageParticipant(_ participant: StageParticipantRecord) async {
        do {
            try await databaseManager.removeStageParticipant(id: participant.id)
            await loadStage()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    var endpointDisplayName: String {
        availableEndpoints.first { $0.id == selectedEndpointID }?.name ?? String(localized: "Unconfigured")
    }

    var selectedProviderDialect: APIProviderDialect {
        if let selectedModelName,
           let selectedModel = availableModelsForEndpoint.first(where: { $0.modelId == selectedModelName }) {
            return selectedModel.providerDialectValue
        }
        return availableModelsForEndpoint.first(where: \.isDefault)?.providerDialectValue
            ?? availableModelsForEndpoint.min(by: { $0.createdAt < $1.createdAt })?.providerDialectValue
            ?? .openAICompatible
    }

    var currentParameters: ModelParameters {
        usesCustomModelParameters ? customModelParameters : inheritedModelParameters
    }

    var inheritedModelParameters: ModelParameters {
        UserDefaults.standard.openChatDefaultModelParameters()
    }

    var customModelParameters: ModelParameters {
        ModelParameters(
            temperature: modelTemperature,
            topP: modelTopP,
            maxTokens: modelMaxTokens,
            frequencyPenalty: 0,
            presencePenalty: 0,
            stop: nil,
            thinkingEnabled: thinkingEnabled,
            thinkingBudget: nil,
            reasoningEffort: reasoningEffort
        )
    }

    func setUsesCustomModelParameters(_ usesCustom: Bool) {
        if usesCustom, !usesCustomModelParameters {
            let inherited = inheritedModelParameters
            modelTemperature = inherited.temperature
            modelTopP = inherited.topP
            modelMaxTokens = inherited.maxTokens ?? 1024
            thinkingEnabled = inherited.isThinkingEnabled
            thinkingBudget = inherited.thinkingBudget ?? 8192
            reasoningEffort = inherited.reasoningEffort
        }
        usesCustomModelParameters = usesCustom
    }

    func syncPrefillNextRole() {
        let nextRole: PrefillInputRole = messages.last?.role == "user" ? .assistantReply : .userMessage
        if prefillNextRole != nextRole {
            prefillNextRole = nextRole
        }
    }

    func syncPrefillNextRole(afterAppendingRole role: String) {
        let nextRole: PrefillInputRole = role == "user" ? .assistantReply : .userMessage
        if prefillNextRole != nextRole {
            prefillNextRole = nextRole
        }
    }

    private func replaceTimelineMessage(with record: MessageRecord) {
        guard let index = messages.firstIndex(where: { $0.id == record.id }) else { return }
        messages[index] = MessageDisplayItem(record: record)
        syncPrefillNextRole()
    }

    private func removeTimelineMessage(id: String) {
        let originalCount = messages.count
        messages.removeAll { $0.id == id }
        if messages.count != originalCount {
            syncPrefillNextRole()
        }
    }

    private func removeTimelineMessages(afterSortOrder sortOrder: Int) {
        let originalCount = messages.count
        messages.removeAll { $0.sortOrder > sortOrder }
        if messages.count != originalCount {
            syncPrefillNextRole()
        }
    }
}

enum PrefillInputRole: Equatable {
    case userMessage
    case assistantReply
}

private extension ModelParameters {
    var isLegacyImplicitConversationDefault: Bool {
        temperature == ModelParameters.openChatDefaultTemperature
            && topP == ModelParameters.openChatDefaultTopP
            && maxTokens == 1024
            && frequencyPenalty == 0
            && presencePenalty == 0
            && (stop?.isEmpty ?? true)
            && !thinkingEnabled
            && thinkingBudget == nil
            && reasoningEffort == .high
    }
}
