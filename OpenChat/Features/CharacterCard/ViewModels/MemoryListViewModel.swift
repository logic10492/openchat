import Foundation
import Observation

@MainActor
@Observable
final class MemoryListViewModel {
    private let databaseManager: DatabaseManager
    private let memoryManager: MemoryManager
    let characterCardId: String

    private(set) var memories: [MemoryEntryRecord] = []
    var searchText: String = ""
    var errorMessage: String?

    var filteredMemories: [MemoryEntryRecord] {
        guard !searchText.isEmpty else { return memories }
        let query = searchText.lowercased()
        return memories.filter { $0.content.lowercased().contains(query) }
    }

    init(
        databaseManager: DatabaseManager,
        memoryManager: MemoryManager,
        characterCardId: String
    ) {
        self.databaseManager = databaseManager
        self.memoryManager = memoryManager
        self.characterCardId = characterCardId
    }

    func loadMemories() async {
        do {
            memories = try await databaseManager.fetchMemories(characterCardId: characterCardId)
        } catch {
            memories = []
            errorMessage = error.localizedDescription
        }
    }

    func deleteMemory(_ id: String) async {
        do {
            try await memoryManager.deleteMemory(id: id)
            memories.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllMemories() async {
        do {
            try await memoryManager.deleteAllMemories(for: characterCardId)
            memories.removeAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
