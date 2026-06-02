import Foundation
import Testing

@testable import OpenChat

@Suite("Skill reference search tool")
struct SkillReferenceSearchToolTests {
    @Test func test_search_reads_bound_skill_references() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "OpenChatSkillReferenceSearchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let store = CharacterSkillBundleStore(rootDirectory: rootDirectory)
        let card = TestHelpers.makeCharacterCard(id: "skill-reference-card", name: "Shiroko")
        let bundle = TestHelpers.makeCharacterSkillBundle(
            id: "skill-reference-bundle",
            characterCardId: card.id,
            bundleRelativePath: "bundle-a",
            skillName: "Shiroko Skill"
        )
        let referencesDirectory = store
            .contentDirectory(bundleRelativePath: bundle.bundleRelativePath)
            .appending(path: "references/research", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: referencesDirectory, withIntermediateDirectories: true)
        try """
        # Expression DNA

        Route planning and cycling details matter. Shiroko checks equipment, time windows, and fallback routes.
        """
        .write(
            to: referencesDirectory.appending(path: "03-expression-dna.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Timeline

        Abydos story milestones and release dates.
        """
        .write(
            to: referencesDirectory.appending(path: "06-timeline.md"),
            atomically: true,
            encoding: .utf8
        )
        try await manager.saveCharacterCard(card, skillBundle: bundle)

        let tool = SkillReferenceSearchTool(databaseManager: manager, store: store)
        let result = try await tool.call(
            SkillReferenceSearchToolInput(
                characterCardId: card.id,
                query: "cycling route equipment",
                limit: 2
            )
        )

        let entry = try #require(result.entries.first)
        #expect(entry.bundleId == bundle.id)
        #expect(entry.characterCardId == card.id)
        #expect(entry.relativePath == "references/research/03-expression-dna.md")
        #expect(entry.title == "Expression DNA")
        #expect(entry.excerpt.contains("Route planning and cycling details matter."))
        #expect(entry.matchedTerms.contains("cycling"))
        #expect(result.trace.candidateFileCount == 2)
        #expect(result.trace.selectedIds == [entry.id])
        #expect(result.trace.omitted.contains { $0.relativePath == "references/research/06-timeline.md" && $0.reason == "noMatch" })
    }

    @Test func test_search_returns_empty_when_character_has_no_skill_bundle() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = CharacterSkillBundleStore(
            rootDirectory: FileManager.default.temporaryDirectory
                .appending(path: "OpenChatSkillReferenceSearchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        let tool = SkillReferenceSearchTool(databaseManager: manager, store: store)

        let result = try await tool.call(
            SkillReferenceSearchToolInput(
                characterCardId: "missing-card",
                query: "cycling",
                limit: 2
            )
        )

        #expect(result.entries.isEmpty)
        #expect(result.trace.fallback == "noBundleOrQuery")
    }

    @Test func test_background_source_maps_reference_results_to_candidates() async throws {
        let result = SkillReferenceSearchResult(
            entries: [
                SkillReferenceSearchEntry(
                    id: "skillReference:bundle-a:references/research/03-expression-dna.md",
                    bundleId: "bundle-a",
                    characterCardId: "card-a",
                    relativePath: "references/research/03-expression-dna.md",
                    title: "Expression DNA",
                    excerpt: "Route planning and equipment checks.",
                    score: 6,
                    matchedTerms: ["route", "equipment"],
                    finalRank: 1
                ),
            ],
            trace: SkillReferenceSearchTrace(
                query: "route equipment",
                candidateFileCount: 2,
                selectedIds: ["skillReference:bundle-a:references/research/03-expression-dna.md"],
                omitted: [],
                fallback: nil
            )
        )

        let candidates = SkillReferenceBackgroundSource.candidates(from: result, characterCardId: "card-a")

        let candidate = try #require(candidates.first)
        #expect(candidate.sourceType == .skillReference)
        #expect(candidate.sourceId == "bundle-a:references/research/03-expression-dna.md")
        #expect(candidate.title == "Expression DNA")
        #expect(candidate.content == "Route planning and equipment checks.")
        #expect(candidate.metadata["relativePath"] == "references/research/03-expression-dna.md")
        #expect(candidate.metadata["matchedTerms"] == "route,equipment")
        #expect(candidate.metadata["characterCardId"] == "card-a")
        #expect(candidate.metadata["reasons"] == "skillReferenceSearch")
    }
}
