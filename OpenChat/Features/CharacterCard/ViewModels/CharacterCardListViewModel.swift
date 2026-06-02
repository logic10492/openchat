import Foundation
import Observation

@MainActor
@Observable
final class CharacterCardListViewModel {
    private let databaseManager: DatabaseManager
    private let appState: AppState
    private let skillBundleStore: CharacterSkillBundleStore?

    private(set) var cards: [CharacterCardRecord] = []
    var searchText = ""
    var selectedTag: String?

    init(
        databaseManager: DatabaseManager,
        appState: AppState,
        skillBundleStore: CharacterSkillBundleStore? = nil
    ) {
        self.databaseManager = databaseManager
        self.appState = appState
        self.skillBundleStore = skillBundleStore
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
            let bundle = try await databaseManager.fetchCharacterSkillBundle(characterCardId: card.id)
            try await databaseManager.deleteCharacterCard(id: card.id)
            cards.removeAll { $0.id == card.id }
            if let bundle, let skillBundleStore {
                do {
                    try skillBundleStore.deleteBundle(bundle)
                } catch {
                    appState.present(error: error.localizedDescription)
                }
            }
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func duplicateCard(_ card: CharacterCardRecord) async {
        let now = Date()
        let duplicateId = UUID().uuidString
        let duplicate = CharacterCardRecord(
            id: duplicateId,
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

        var copiedBundle: CharacterSkillBundleRecord?
        do {
            if let sourceBundle = try await databaseManager.fetchCharacterSkillBundle(characterCardId: card.id),
               let skillBundleStore {
                let duplicateBundle = try skillBundleStore.duplicateBundle(
                    sourceBundle,
                    characterCardId: duplicateId,
                    now: now
                )
                copiedBundle = duplicateBundle
                try await databaseManager.saveCharacterCard(duplicate, skillBundle: duplicateBundle)
            } else {
                try await databaseManager.saveCharacterCard(duplicate)
            }
            cards.insert(duplicate, at: 0)
        } catch {
            if let copiedBundle, let skillBundleStore {
                try? skillBundleStore.deleteBundle(copiedBundle)
            }
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

    func importFile(data: Data, sourceFileName: String?) async throws -> CharacterCardRecord {
        if CharacterSkillBundleImportFormat.isZipImport(data: data, sourceFileName: sourceFileName) {
            return try await importSkillBundleArchive(data: data, sourceFileName: sourceFileName)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw CharacterCardImportError.invalidJSON
        }
        let parsedCard = try CharacterCardImportFormat.parse(text: text)
        return try await importCard(parsedCard)
    }

    func importSkillBundleArchive(data: Data, sourceFileName: String?) async throws -> CharacterCardRecord {
        guard let skillBundleStore else {
            throw CharacterSkillBundleImportError.skillBundleStoreUnavailable
        }

        let prepared = try CharacterSkillBundleImportFormat.prepareImport(
            archiveData: data,
            sourceFileName: sourceFileName,
            store: skillBundleStore
        )

        do {
            try await databaseManager.saveCharacterCard(prepared.card, skillBundle: prepared.bundle)
            cards.insert(prepared.card, at: 0)
            return prepared.card
        } catch {
            try? skillBundleStore.deleteBundle(prepared.bundle)
            appState.present(error: error.localizedDescription)
            throw error
        }
    }
}
