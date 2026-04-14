import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    let databaseManager: DatabaseManager
    let apiClient: APIClient
    let contextManager: ContextManager
    let appState: AppState

    var conversation: ConversationRecord
    var messages: [MessageDisplayItem] = []
    var isGenerating = false
    var tokenUsage: TokenUsageReport?
    private(set) var availableEndpoints: [APIEndpointRecord] = []
    private(set) var availableCharacterCards: [CharacterCardRecord] = []
    private(set) var availableWorldBooks: [WorldBookRecord] = []

    var inputText = ""
    var selectedEndpointID: String?
    var selectedCharacterCardID: String?
    var selectedWorldBookID: String?
    var selectedContextStrategy: ContextStrategy
    var customScenario = ""
    var modelTemperature = AppConstants.defaultTemperature
    var modelTopP = AppConstants.defaultTopP
    var modelMaxTokens = 1024

    @ObservationIgnored
    var streamTask: Task<Void, Never>?

    init(
        conversation: ConversationRecord,
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        contextManager: ContextManager,
        appState: AppState
    ) {
        self.conversation = conversation
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.contextManager = contextManager
        self.appState = appState
        selectedEndpointID = conversation.apiEndpointId
        selectedCharacterCardID = conversation.characterCardId
        selectedWorldBookID = conversation.worldBookId
        selectedContextStrategy = ContextStrategy(rawValue: conversation.contextStrategy) ?? .truncation
        customScenario = conversation.customScenario ?? ""

        if let parameters = conversation.decodedModelParameters {
            modelTemperature = parameters.temperature
            modelTopP = parameters.topP
            modelMaxTokens = parameters.maxTokens ?? 1024
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
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func sendMessage() async {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !isGenerating else { return }

        do {
            try await generateResponse(for: trimmedInput, persistUserMessage: true)
            inputText = ""
        } catch {
            appState.present(error: error.localizedDescription)
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
            try await databaseManager.deleteMessage(id: messageId)
            await loadMessages()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func saveConversationSettings() async {
        conversation.apiEndpointId = selectedEndpointID
        conversation.characterCardId = selectedCharacterCardID
        conversation.worldBookId = selectedWorldBookID
        conversation.contextStrategy = selectedContextStrategy.rawValue
        conversation.customScenario = customScenario.nilIfBlank
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

    var currentParameters: ModelParameters {
        ModelParameters(
            temperature: modelTemperature,
            topP: modelTopP,
            maxTokens: modelMaxTokens,
            frequencyPenalty: 0,
            presencePenalty: 0,
            stop: nil
        )
    }
}
