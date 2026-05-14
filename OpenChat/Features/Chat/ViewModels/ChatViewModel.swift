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
    let titleGenerator: TitleGenerator
    let apiKeyStore: any APIKeyStore
    let appState: AppState

    var conversation: ConversationRecord
    var messages: [MessageDisplayItem] = []
    var isGenerating = false
    var isGeneratingTitle = false
    var extractionPhase: MemoryExtractionPhase = .idle
    var tokenUsage: TokenUsageReport?
    private(set) var availableEndpoints: [APIEndpointRecord] = []
    private(set) var availableCharacterCards: [CharacterCardRecord] = []
    private(set) var availableWorldBooks: [WorldBookRecord] = []
    private(set) var availableModelsForEndpoint: [EndpointModelRecord] = []

    var inputText = ""
    var selectedEndpointID: String?
    var selectedModelName: String?
    var selectedCharacterCardID: String?
    var selectedContextStrategy: ContextStrategy
    var selectedCompressionMode: CompressionMode
    var customScenario = ""
    var slowPlotMode: Bool
    var modelTemperature = AppConstants.defaultTemperature
    var modelTopP = AppConstants.defaultTopP
    var modelMaxTokens = 1024
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

    @ObservationIgnored
    var streamTask: Task<Void, Never>?
    static let minimumPendingMessagesForExtraction = MemoryManager.minimumMessagesForExtraction

    init(
        conversation: ConversationRecord,
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        contextManager: ContextManager,
        memoryManager: MemoryManager,
        titleGenerator: TitleGenerator,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        appState: AppState
    ) {
        self.conversation = conversation
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.contextManager = contextManager
        self.memoryManager = memoryManager
        self.titleGenerator = titleGenerator
        self.apiKeyStore = apiKeyStore
        self.appState = appState
        selectedEndpointID = conversation.apiEndpointId
        selectedModelName = conversation.modelName
        selectedCharacterCardID = conversation.characterCardId
        selectedContextStrategy = ContextStrategy(rawValue: conversation.contextStrategy) ?? .truncation
        selectedCompressionMode = conversation.compressionModeValue
        customScenario = conversation.customScenario ?? ""
        slowPlotMode = conversation.slowPlotMode
        showDetailedStats = UserDefaults.standard.bool(forKey: "show_detailed_stats")

        if let parameters = conversation.decodedModelParameters {
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
            let records = try await databaseManager.fetchMessages(conversationId: conversation.id)
            messages = records.map(MessageDisplayItem.init(record:))
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
        } catch {
            appState.present(error: error.localizedDescription)
        }
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

        // Generate title first if this is a fresh conversation
        if !conversation.isTitleGenerated {
            await generateTitleIfNeeded(userMessage: trimmedInput)
        }

        do {
            try await generateResponse(for: trimmedInput, persistUserMessage: true)
            inputText = ""
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func renameConversation(newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
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
        do {
            let records = try await databaseManager.fetchMessages(conversationId: conversation.id)
            guard var target = records.first(where: { $0.id == messageId }) else { return }
            target.content = newContent
            target.tokenCount = TokenCounter.count(newContent)
            try await databaseManager.saveMessage(target)
            try await databaseManager.deleteCompressionCheckpoints(
                conversationId: conversation.id,
                sourceEndAtOrAfter: target.sortOrder
            )
            try await databaseManager.deleteMessages(
                conversationId: conversation.id,
                afterSortOrder: target.sortOrder
            )
            await loadMessages()
            try await generateResponse(for: newContent, persistUserMessage: false)
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
            await loadMessages()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func saveConversationSettings() async {
        conversation.apiEndpointId = selectedEndpointID
        conversation.modelName = selectedModelName
        conversation.characterCardId = selectedCharacterCardID
        conversation.contextStrategy = selectedContextStrategy.rawValue
        conversation.compressionMode = selectedCompressionMode.rawValue
        conversation.customScenario = customScenario.nilIfBlank
        conversation.slowPlotMode = slowPlotMode
        conversation.modelParameters = RecordCoders.encode(currentParameters)
        conversation.updatedAt = .now

        do {
            try await databaseManager.saveConversation(conversation)
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
        ModelParameters(
            temperature: modelTemperature,
            topP: modelTopP,
            maxTokens: modelMaxTokens,
            frequencyPenalty: 0,
            presencePenalty: 0,
            stop: nil,
            thinkingBudget: thinkingEnabled ? thinkingBudget : nil,
            reasoningEffort: reasoningEffort
        )
    }
}
