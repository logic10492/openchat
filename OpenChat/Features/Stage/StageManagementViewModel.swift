import Foundation
import Observation

@MainActor
@Observable
final class StageManagementViewModel {
    private let databaseManager: DatabaseManager
    private let appState: AppState

    private(set) var stages: [StageListItem] = []
    private(set) var isLoading = false
    var errorMessage: String?

    init(
        databaseManager: DatabaseManager,
        appState: AppState
    ) {
        self.databaseManager = databaseManager
        self.appState = appState
    }

    func loadStages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            stages = try await databaseManager.fetchStageListItems()
            errorMessage = nil
        } catch {
            stages = []
            errorMessage = error.localizedDescription
        }
    }

    func openConversation(_ item: StageListItem) {
        appState.selectedConversationID = item.conversation.id
        appState.columnVisibility = .automatic
    }
}
