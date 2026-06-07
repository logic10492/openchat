import Foundation
import Observation

@MainActor
@Observable
final class CharacterSkillBundleEditorViewModel {
    private let databaseManager: DatabaseManager
    private let skillBundleStore: CharacterSkillBundleStore

    private(set) var editingCard: CharacterCardRecord
    private(set) var editingBundle: CharacterSkillBundleRecord?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var skillMarkdown = ""
    var worldBookId: String?
    private(set) var availableWorldBooks: [WorldBookRecord] = []
    var referenceDrafts: [CharacterSkillReferenceDraft] = []
    var errorMessage: String?

    init(
        databaseManager: DatabaseManager,
        skillBundleStore: CharacterSkillBundleStore,
        editingCard: CharacterCardRecord,
        editingBundle: CharacterSkillBundleRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.skillBundleStore = skillBundleStore
        self.editingCard = editingCard
        self.editingBundle = editingBundle
        self.worldBookId = editingCard.worldBookId
    }

    var skillName: String {
        (try? CharacterSkillMarkdownMetadata(markdown: skillMarkdown))?.name
            ?? editingBundle?.skillName
            ?? editingCard.name
    }

    var skillDescription: String {
        let metadata = try? CharacterSkillMarkdownMetadata(markdown: skillMarkdown)
        return metadata?.description
            ?? metadata?.firstParagraph
            ?? editingBundle?.skillDescription
            ?? editingCard.personality
            ?? ""
    }

    var roleSkillPreview: String {
        PromptAssembler.makeRoleSkillMessageContent(
            RoleSkillPromptMaterial(
                name: skillName,
                source: "character_skill_bundle:\(editingBundle?.id ?? "pending"):\(editingBundle?.skillMarkdownSha256 ?? "pending")",
                skillMarkdown: skillMarkdown
            )
        )
    }

    var isValid: Bool {
        validationErrors.isEmpty
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if skillMarkdown.nilIfBlank == nil {
            errors.append(CharacterSkillBundleEditorError.emptySkillMarkdown.localizedDescription)
        }
        if (try? CharacterSkillMarkdownMetadata(markdown: skillMarkdown))?.name == nil {
            errors.append(CharacterSkillBundleEditorError.missingSkillName.localizedDescription)
        }
        return errors
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bundle = try await databaseManager.fetchCharacterSkillBundle(characterCardId: editingCard.id)
            guard let bundle else {
                throw CharacterSkillBundleEditorError.missingBundle
            }
            availableWorldBooks = try await databaseManager.fetchWorldBooks()
            editingBundle = bundle
            skillMarkdown = try skillBundleStore.readSkillMarkdown(for: bundle)

            var drafts: [CharacterSkillReferenceDraft] = []
            for file in try skillBundleStore.referenceMarkdownFiles(for: bundle) {
                let markdown = try skillBundleStore.readReferenceMarkdown(for: bundle, relativePath: file.relativePath)
                drafts.append(CharacterSkillReferenceDraft(relativePath: file.relativePath, markdown: markdown))
            }
            referenceDrafts = drafts
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async throws -> CharacterCardRecord {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            guard let bundle = editingBundle else {
                throw CharacterSkillBundleEditorError.missingBundle
            }
            guard skillMarkdown.nilIfBlank != nil else {
                throw CharacterSkillBundleEditorError.emptySkillMarkdown
            }
            let metadata = try CharacterSkillMarkdownMetadata(markdown: skillMarkdown)
            guard let name = metadata.name else {
                throw CharacterSkillBundleEditorError.missingSkillName
            }

            let originalSkillMarkdown = try skillBundleStore.readSkillMarkdown(for: bundle)
            let originalReferenceMarkdowns = try referenceDrafts.reduce(into: [String: String]()) { values, draft in
                values[draft.relativePath] = try skillBundleStore.readReferenceMarkdown(
                    for: bundle,
                    relativePath: draft.relativePath
                )
            }
            let skillManifestEntry = try skillBundleStore.writeSkillMarkdown(skillMarkdown, for: bundle)
            for draft in referenceDrafts {
                _ = try skillBundleStore.writeReferenceMarkdown(
                    draft.markdown,
                    for: bundle,
                    relativePath: draft.relativePath
                )
            }

            let now = Date()
            let manifest = try skillBundleStore.contentFileManifestEntries(for: bundle)
            let skillDescription = metadata.description ?? metadata.firstParagraph ?? name
            let displayName = metadata.firstHeading ?? name
            let updatedBundle = CharacterSkillBundleRecord(
                id: bundle.id,
                characterCardId: bundle.characterCardId,
                sourceKind: bundle.sourceKind,
                sourceFileName: bundle.sourceFileName,
                sourceArchiveSha256: bundle.sourceArchiveSha256,
                bundleRelativePath: bundle.bundleRelativePath,
                skillMarkdownRelativePath: bundle.skillMarkdownRelativePath,
                skillMarkdownSha256: skillManifestEntry.sha256,
                skillName: name,
                skillDescription: skillDescription,
                skillShortDescription: metadata.scalar("short_description") ?? bundle.skillShortDescription,
                frontmatterJSON: metadata.frontmatterJSON,
                agentsOpenAIYamlJSON: bundle.agentsOpenAIYamlJSON,
                fileManifestJSON: try CharacterSkillJSONCoder.encodeJSON(manifest),
                materializationMode: bundle.materializationMode,
                createdAt: bundle.createdAt,
                updatedAt: now
            )
            let updatedCard = CharacterCardRecord(
                id: editingCard.id,
                name: displayName,
                avatar: editingCard.avatar,
                personality: skillDescription,
                appearance: editingCard.appearance,
                physique: editingCard.physique,
                speechStyle: editingCard.speechStyle,
                backstory: editingCard.backstory,
                systemPrompt: editingCard.systemPrompt ?? "Use the attached role skill as the authoritative behavior guide.",
                scenario: editingCard.scenario,
                exampleDialogs: editingCard.exampleDialogs,
                creatorNotes: editingCard.creatorNotes,
                tags: editingCard.tags,
                worldBookId: worldBookId,
                createdAt: editingCard.createdAt,
                updatedAt: now
            )

            do {
                try await databaseManager.saveCharacterCard(updatedCard, skillBundle: updatedBundle)
            } catch {
                _ = try? skillBundleStore.writeSkillMarkdown(originalSkillMarkdown, for: bundle)
                for (relativePath, markdown) in originalReferenceMarkdowns {
                    _ = try? skillBundleStore.writeReferenceMarkdown(markdown, for: bundle, relativePath: relativePath)
                }
                throw error
            }
            editingCard = updatedCard
            editingBundle = updatedBundle
            return updatedCard
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
