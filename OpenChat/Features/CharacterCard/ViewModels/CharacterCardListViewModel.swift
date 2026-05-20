import Foundation
import Observation

@MainActor
@Observable
final class CharacterCardListViewModel {
    private let databaseManager: DatabaseManager
    private let appState: AppState

    private(set) var cards: [CharacterCardRecord] = []
    var searchText = ""
    var selectedTag: String?

    init(
        databaseManager: DatabaseManager,
        appState: AppState
    ) {
        self.databaseManager = databaseManager
        self.appState = appState
    }

    var filteredCards: [CharacterCardRecord] {
        cards.filter { card in
            let matchesSearch = searchText.nilIfBlank == nil ||
                card.name.localizedCaseInsensitiveContains(searchText) ||
                card.decodedTags.contains { $0.localizedCaseInsensitiveContains(searchText) }

            let matchesTag = selectedTag == nil || card.decodedTags.contains(selectedTag!)
            return matchesSearch && matchesTag
        }
    }

    var allTags: [String] {
        Array(Set(cards.flatMap(\.decodedTags))).sorted()
    }

    func loadCards() async {
        do {
            cards = try await databaseManager.fetchCharacterCards()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func deleteCard(_ card: CharacterCardRecord) async {
        do {
            try await databaseManager.deleteCharacterCard(id: card.id)
            cards.removeAll { $0.id == card.id }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func duplicateCard(_ card: CharacterCardRecord) async {
        let now = Date()
        let duplicate = CharacterCardRecord(
            id: UUID().uuidString,
            name: "\(card.name) Copy",
            avatar: card.avatar,
            personality: card.personality,
            appearance: card.appearance,
            physique: card.physique,
            speechStyle: card.speechStyle,
            backstory: card.backstory,
            systemPrompt: card.systemPrompt,
            scenario: card.scenario,
            exampleDialogs: card.exampleDialogs,
            creatorNotes: card.creatorNotes,
            tags: card.tags,
            worldBookId: card.worldBookId,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await databaseManager.saveCharacterCard(duplicate)
            cards.insert(duplicate, at: 0)
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func importCard(_ parsedCard: CharacterCardImportFormat.ParsedCard) async throws -> CharacterCardRecord {
        let now = Date()
        let record = CharacterCardRecord(
            id: UUID().uuidString,
            name: parsedCard.name,
            avatar: nil,
            personality: parsedCard.personality,
            appearance: parsedCard.appearance,
            physique: parsedCard.physique,
            speechStyle: parsedCard.speechStyle,
            backstory: parsedCard.backstory,
            systemPrompt: parsedCard.systemPrompt,
            scenario: parsedCard.scenario,
            exampleDialogs: RecordCoders.encode(parsedCard.exampleDialogs),
            creatorNotes: parsedCard.creatorNotes,
            tags: RecordCoders.encode(parsedCard.tags),
            worldBookId: nil,
            createdAt: now,
            updatedAt: now
        )

        do {
            try await databaseManager.saveCharacterCard(record)
            cards.insert(record, at: 0)
            return record
        } catch {
            appState.present(error: error.localizedDescription)
            throw error
        }
    }
}
