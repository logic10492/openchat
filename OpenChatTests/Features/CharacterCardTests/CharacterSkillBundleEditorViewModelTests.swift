import Foundation
import Testing

@testable import OpenChat

@MainActor
@Suite("Character skill bundle editor")
struct CharacterSkillBundleEditorViewModelTests {
    @Test func test_load_reads_skill_markdown_and_references() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let viewModel = CharacterSkillBundleEditorViewModel(
            databaseManager: fixture.manager,
            skillBundleStore: fixture.store,
            editingCard: fixture.card,
            editingBundle: fixture.bundle
        )

        await viewModel.load()

        #expect(viewModel.skillMarkdown == fixture.skillMarkdown)
        #expect(viewModel.skillName == "shiroko-perspective")
        #expect(viewModel.referenceDrafts == [
            CharacterSkillReferenceDraft(
                relativePath: "references/research.md",
                markdown: fixture.referenceMarkdown
            ),
        ])
    }

    @Test func test_save_updates_skill_file_bundle_metadata_card_summary_and_runtime_material() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let viewModel = CharacterSkillBundleEditorViewModel(
            databaseManager: fixture.manager,
            skillBundleStore: fixture.store,
            editingCard: fixture.card,
            editingBundle: fixture.bundle
        )
        await viewModel.load()
        let updatedSkillMarkdown = """
        ---
        name: shiroko-updated
        description: Updated tactical role skill.
        short_description: Updated short summary
        ---

        # Updated Shiroko Role

        Use updated field notes and keep replies compact.
        """
        let updatedReferenceMarkdown = """
        # Equipment Notes

        Updated reference material is now authoritative.
        """
        viewModel.skillMarkdown = updatedSkillMarkdown
        viewModel.referenceDrafts[0].markdown = updatedReferenceMarkdown

        let savedCard = try await viewModel.save()

        #expect(savedCard.name == "Updated Shiroko Role")
        #expect(savedCard.personality == "Updated tactical role skill.")

        let savedBundle = try #require(try await fixture.manager.fetchCharacterSkillBundle(characterCardId: savedCard.id))
        #expect(savedBundle.skillName == "shiroko-updated")
        #expect(savedBundle.skillDescription == "Updated tactical role skill.")
        #expect(savedBundle.skillShortDescription == "Updated short summary")
        #expect(savedBundle.skillMarkdownSha256 == SHA256Hex.hash(text: updatedSkillMarkdown))
        #expect(savedBundle.frontmatterJSON.contains("shiroko-updated"))

        let manifest = try JSONDecoder().decode(
            [CharacterSkillBundleFileManifestEntry].self,
            from: Data(savedBundle.fileManifestJSON.utf8)
        )
        #expect(manifest.map(\.relativePath) == ["SKILL.md", "references/research.md"])
        #expect(
            try fixture.store.readReferenceMarkdown(
                for: savedBundle,
                relativePath: "references/research.md"
            ) == updatedReferenceMarkdown
        )

        let materializer = CharacterSkillBundleMaterializer(databaseManager: fixture.manager, store: fixture.store)
        let material = try #require(try await materializer.materialize(characterCardId: savedCard.id))
        #expect(material.name == "shiroko-updated")
        #expect(material.skillMarkdown == updatedSkillMarkdown)
    }

    @Test func test_save_requires_skill_frontmatter_name() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
        let viewModel = CharacterSkillBundleEditorViewModel(
            databaseManager: fixture.manager,
            skillBundleStore: fixture.store,
            editingCard: fixture.card,
            editingBundle: fixture.bundle
        )
        await viewModel.load()
        viewModel.skillMarkdown = """
        ---
        description: Missing name.
        ---

        # Missing Name
        """

        await #expect(throws: CharacterSkillBundleEditorError.missingSkillName) {
            _ = try await viewModel.save()
        }
    }

    private func makeFixture() async throws -> CharacterSkillBundleEditorFixture {
        let manager = try TestHelpers.makeDatabaseManager()
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "OpenChatSkillBundleEditorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = CharacterSkillBundleStore(rootDirectory: rootDirectory)
        let card = TestHelpers.makeCharacterCard(id: "skill-editor-card", name: "Shiroko Role")
        let skillMarkdown = """
        ---
        name: shiroko-perspective
        description: Quiet tactical role skill.
        ---

        # Shiroko Role

        Keep tactical focus.
        """
        let referenceMarkdown = """
        # Equipment Notes

        Cycling equipment and route planning are important.
        """
        let bundleId = UUID().uuidString
        let manifest = try store.writeImportedBundle(
            bundleId: bundleId,
            files: [
                CharacterSkillBundleArchiveFile(relativePath: "SKILL.md", data: Data(skillMarkdown.utf8)),
                CharacterSkillBundleArchiveFile(relativePath: "references/research.md", data: Data(referenceMarkdown.utf8)),
            ]
        )
        let bundle = CharacterSkillBundleRecord(
            id: "skill-editor-bundle",
            characterCardId: card.id,
            sourceKind: "zip",
            sourceFileName: "shiroko-role.zip",
            sourceArchiveSha256: "archive-sha",
            bundleRelativePath: bundleId,
            skillMarkdownRelativePath: "SKILL.md",
            skillMarkdownSha256: SHA256Hex.hash(text: skillMarkdown),
            skillName: "shiroko-perspective",
            skillDescription: "Quiet tactical role skill.",
            skillShortDescription: nil,
            frontmatterJSON: try CharacterSkillMarkdownMetadata(markdown: skillMarkdown).frontmatterJSON,
            agentsOpenAIYamlJSON: nil,
            fileManifestJSON: try CharacterSkillJSONCoder.encodeJSON(manifest),
            materializationMode: "fullSkillMarkdown",
            createdAt: TestDateFactory.now(),
            updatedAt: TestDateFactory.now()
        )
        try await manager.saveCharacterCard(card, skillBundle: bundle)
        return CharacterSkillBundleEditorFixture(
            manager: manager,
            store: store,
            rootDirectory: rootDirectory,
            card: card,
            bundle: bundle,
            skillMarkdown: skillMarkdown,
            referenceMarkdown: referenceMarkdown
        )
    }
}

private struct CharacterSkillBundleEditorFixture {
    let manager: DatabaseManager
    let store: CharacterSkillBundleStore
    let rootDirectory: URL
    let card: CharacterCardRecord
    let bundle: CharacterSkillBundleRecord
    let skillMarkdown: String
    let referenceMarkdown: String
}
