import Foundation
import Observation

@MainActor
@Observable
final class ConversationListViewModel {
    private let databaseManager: DatabaseManager
    private let appState: AppState

    private(set) var conversations: [ConversationRecord] = []
    private(set) var isLoading = false

    init(
        databaseManager: DatabaseManager,
        appState: AppState
    ) {
        self.databaseManager = databaseManager
        self.appState = appState
    }

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await databaseManager.fetchConversations()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func createConversation() async -> ConversationRecord? {
        let now = Date()
        let endpoint = try? await databaseManager.fetchDefaultEndpoint()
        let conversation = ConversationRecord(
            id: UUID().uuidString,
            title: String(localized: "New Chat"),
            characterCardId: nil,
            worldBookId: nil,
            apiEndpointId: endpoint?.id,
            contextStrategy: AppConstants.defaultContextStrategy.rawValue,
            customScenario: nil,
            modelParameters: nil,
            isPinned: false,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await databaseManager.saveConversation(conversation)
            conversations.insert(conversation, at: 0)
            appState.selectedConversationID = conversation.id
            return conversation
        } catch {
            appState.present(error: error.localizedDescription)
            return nil
        }
    }

    func deleteConversation(_ conversation: ConversationRecord) async {
        do {
            try await databaseManager.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if appState.selectedConversationID == conversation.id {
                appState.selectedConversationID = conversations.first?.id
            }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func conversation(id: String) -> ConversationRecord? {
        conversations.first { $0.id == id }
    }
}
