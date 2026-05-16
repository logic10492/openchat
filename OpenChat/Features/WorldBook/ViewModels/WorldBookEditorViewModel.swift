import Foundation
import Observation

@MainActor
@Observable
final class WorldBookEditorViewModel {
    private let databaseManager: DatabaseManager
    private let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer
    private var savedWorldBook: WorldBookRecord?

    var name = ""
    var description = ""
    var isEnabled = true
    var entries: [WorldBookEntryRecord] = []
    private(set) var characters: [CharacterCardRecord] = []
    private(set) var isSaving = false
    var errorMessage: String?
    var indexingWarningMessage: String?
    let editingWorldBook: WorldBookRecord?
    var currentWorldBookId: String? {
        (editingWorldBook ?? savedWorldBook)?.id
    }

    init(
        databaseManager: DatabaseManager,
        worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer,
        editingWorldBook: WorldBookRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.worldBookEmbeddingIndexer = worldBookEmbeddingIndexer
        self.editingWorldBook = editingWorldBook
        if let editingWorldBook {
            name = editingWorldBook.name
            description = editingWorldBook.description ?? ""
            isEnabled = editingWorldBook.isEnabled
        }
    }

    func loadEntries() async {
        do {
            entries = try await databaseManager.fetchWorldBookEntries(worldBookId: currentWorldBookId)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    func loadCharacters() async {
        guard let worldBookId = currentWorldBookId else {
            characters = []
            return
        }
        do {
            characters = try await databaseManager.fetchCharacterCards(worldBookId: worldBookId)
        } catch {
            characters = []
            errorMessage = error.localizedDescription
        }
    }

    func save() async throws -> WorldBookRecord {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let now = Date()
            let existingWorldBook = editingWorldBook ?? savedWorldBook
            let record = WorldBookRecord(
                id: existingWorldBook?.id ?? UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.nilIfBlank,
                isEnabled: isEnabled,
                createdAt: existingWorldBook?.createdAt ?? now,
                updatedAt: now
            )
            try await databaseManager.saveWorldBook(record)
            savedWorldBook = record
            return record
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func saveEntry(_ entry: WorldBookEntryRecord) async throws {
        do {
            let worldBook = try await ensureWorldBookSaved()
            var entryToSave = entry
            if entryToSave.worldBookId != worldBook.id {
                entryToSave.worldBookId = worldBook.id
                entryToSave.updatedAt = Date()
            }

            try await databaseManager.saveWorldBookEntry(entryToSave)
            await indexSavedEntry(entryToSave)
            entries = try await databaseManager.fetchWorldBookEntries(worldBookId: worldBook.id)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func importEntries(_ parsedEntries: [WorldBookImportFormat.ParsedEntry]) async throws -> WorldBookImportResult {
        do {
            let worldBook = try await save()
            let now = Date()
            let entriesToSave = parsedEntries.map { parsed in
                WorldBookEntryRecord(
                    id: UUID().uuidString,
                    worldBookId: worldBook.id,
                    title: parsed.title,
                    content: parsed.content,
                    keywords: RecordCoders.encode(parsed.keywords) ?? "[]",
                    priority: parsed.priority,
                    isEnabled: true,
                    position: parsed.position,
                    createdAt: now,
                    updatedAt: now
                )
            }

            try await databaseManager.saveWorldBookEntries(entriesToSave)
            let indexingResult = try await worldBookEmbeddingIndexer.index(entries: entriesToSave)
            entries = try await databaseManager.fetchWorldBookEntries(worldBookId: worldBook.id)

            let warnings = parsedEntries.flatMap(\.warnings) + indexingResult.failed.map { failure in
                String.localizedStringWithFormat(
                    String(localized: "World book index warning: %@"),
                    failure.errorDescription
                )
            }
            indexingWarningMessage = warnings.isEmpty ? nil : warnings.joined(separator: "\n")

            return WorldBookImportResult(
                importedCount: entriesToSave.count,
                indexedCount: indexingResult.indexedCount,
                skippedFreshCount: indexingResult.skippedFreshCount,
                failedIndexingCount: indexingResult.failed.count,
                warnings: warnings
            )
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func indexSavedEntry(_ entry: WorldBookEntryRecord) async {
        do {
            _ = try await worldBookEmbeddingIndexer.index(entry: entry)
            indexingWarningMessage = nil
        } catch {
            indexingWarningMessage = String.localizedStringWithFormat(
                String(localized: "World book index warning: %@"),
                error.localizedDescription
            )
        }
    }

    private func ensureWorldBookSaved() async throws -> WorldBookRecord {
        if let existing = editingWorldBook ?? savedWorldBook {
            return existing
        }
        return try await save()
    }
}

struct WorldBookImportResult: Sendable {
    let importedCount: Int
    let indexedCount: Int
    let skippedFreshCount: Int
    let failedIndexingCount: Int
    let warnings: [String]
}
