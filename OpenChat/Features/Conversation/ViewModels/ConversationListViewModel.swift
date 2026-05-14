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
            apiEndpointId: endpoint?.id,
            modelName: nil,
            contextStrategy: AppConstants.defaultContextStrategy.rawValue,
            compressionMode: CompressionMode.standard.rawValue,
            customScenario: nil,
            modelParameters: nil,
            slowPlotMode: true,
            isTitleGenerated: false,
            isPinned: false,
            lastExtractedSortOrder: nil,
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

    func renameConversation(_ id: String, newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            guard var conversation = try await databaseManager.fetchConversation(id: id) else { return }
            conversation.title = trimmed
            conversation.isTitleGenerated = true
            conversation.updatedAt = .now
            try await databaseManager.saveConversation(conversation)
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = conversation
            }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func conversation(id: String) -> ConversationRecord? {
        conversations.first { $0.id == id }
    }
}
