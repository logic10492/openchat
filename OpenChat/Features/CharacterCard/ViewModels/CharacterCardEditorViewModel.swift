import Foundation
import Observation

@MainActor
@Observable
final class CharacterCardEditorViewModel {
    private let databaseManager: DatabaseManager

    var name = ""
    var avatarData: Data?
    var personality = ""
    var appearance = ""
    var physique = ""
    var speechStyle = ""
    var backstory = ""
    var systemPrompt = ""
    var scenario = ""
    var exampleDialogs: [ChatMessage] = []
    var tags: [String] = []
    var creatorNotes = ""
    let editingCard: CharacterCardRecord?

    init(
        databaseManager: DatabaseManager,
        editingCard: CharacterCardRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.editingCard = editingCard
        if let editingCard {
            loadFromRecord(editingCard)
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var validationErrors: [String] {
        isValid ? [] : [String(localized: "Name is required.")]
    }

    func loadFromRecord(_ record: CharacterCardRecord) {
        name = record.name
        avatarData = record.avatar
        personality = record.personality ?? ""
        appearance = record.appearance ?? ""
        physique = record.physique ?? ""
        speechStyle = record.speechStyle ?? ""
        backstory = record.backstory ?? ""
        systemPrompt = record.systemPrompt ?? ""
        scenario = record.scenario ?? ""
        exampleDialogs = record.decodedExampleDialogs
        tags = record.decodedTags
        creatorNotes = record.creatorNotes ?? ""
    }

    func save() async throws -> CharacterCardRecord {
        let now = Date()
        let record = CharacterCardRecord(
            id: editingCard?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: avatarData,
            personality: personality.nilIfBlank,
            appearance: appearance.nilIfBlank,
            physique: physique.nilIfBlank,
            speechStyle: speechStyle.nilIfBlank,
            backstory: backstory.nilIfBlank,
            systemPrompt: systemPrompt.nilIfBlank,
            scenario: scenario.nilIfBlank,
            exampleDialogs: RecordCoders.encode(exampleDialogs),
            creatorNotes: creatorNotes.nilIfBlank,
            tags: RecordCoders.encode(tags),
            createdAt: editingCard?.createdAt ?? now,
            updatedAt: now
        )
        try await databaseManager.saveCharacterCard(record)
        return record
    }
}
