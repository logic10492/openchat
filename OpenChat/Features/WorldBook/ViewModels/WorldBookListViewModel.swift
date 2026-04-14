import Foundation
import Observation

@MainActor
@Observable
final class WorldBookListViewModel {
    private let databaseManager: DatabaseManager
    private let appState: AppState

    private(set) var worldBooks: [WorldBookRecord] = []

    init(
        databaseManager: DatabaseManager,
        appState: AppState
    ) {
        self.databaseManager = databaseManager
        self.appState = appState
    }

    func loadWorldBooks() async {
        do {
            worldBooks = try await databaseManager.fetchWorldBooks()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func toggleEnabled(_ worldBook: WorldBookRecord) async {
        var updated = worldBook
        updated.isEnabled.toggle()
        updated.updatedAt = .now
        do {
            try await databaseManager.saveWorldBook(updated)
            await loadWorldBooks()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func deleteWorldBook(_ worldBook: WorldBookRecord) async {
        do {
            try await databaseManager.deleteWorldBook(id: worldBook.id)
            worldBooks.removeAll { $0.id == worldBook.id }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }
}
