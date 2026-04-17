import Foundation
import Observation

@MainActor
@Observable
final class WorldBookEditorViewModel {
    private let databaseManager: DatabaseManager

    var name = ""
    var description = ""
    var isEnabled = true
    var entries: [WorldBookEntryRecord] = []
    private(set) var characters: [CharacterCardRecord] = []
    let editingWorldBook: WorldBookRecord?

    init(
        databaseManager: DatabaseManager,
        editingWorldBook: WorldBookRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.editingWorldBook = editingWorldBook
        if let editingWorldBook {
            name = editingWorldBook.name
            description = editingWorldBook.description ?? ""
            isEnabled = editingWorldBook.isEnabled
        }
    }

    func loadEntries() async {
        do {
            entries = try await databaseManager.fetchWorldBookEntries(worldBookId: editingWorldBook?.id)
        } catch {
            entries = []
        }
    }

    func loadCharacters() async {
        guard let worldBookId = editingWorldBook?.id else {
            characters = []
            return
        }
        characters = (try? await databaseManager.fetchCharacterCards(worldBookId: worldBookId)) ?? []
    }

    func save() async throws -> WorldBookRecord {
        let now = Date()
        let record = WorldBookRecord(
            id: editingWorldBook?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.nilIfBlank,
            isEnabled: isEnabled,
            createdAt: editingWorldBook?.createdAt ?? now,
            updatedAt: now
        )
        try await databaseManager.saveWorldBook(record)
        return record
    }

    func saveEntry(_ entry: WorldBookEntryRecord) async throws {
        try await databaseManager.saveWorldBookEntry(entry)
        entries = try await databaseManager.fetchWorldBookEntries(worldBookId: entry.worldBookId)
    }
}
