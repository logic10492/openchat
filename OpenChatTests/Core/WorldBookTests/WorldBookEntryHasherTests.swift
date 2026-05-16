import Foundation
import Testing

@testable import OpenChat

@Suite("WorldBookEntryHasher")
struct WorldBookEntryHasherTests {
    @Test func test_hash_is_stable_for_same_text_model_dimension() {
        let first = WorldBookEntryHasher.hash(
            embeddingText: "Title: Gate",
            modelId: "model-a",
            dimension: 384
        )
        let second = WorldBookEntryHasher.hash(
            embeddingText: "Title: Gate",
            modelId: "model-a",
            dimension: 384
        )

        #expect(first == second)
        #expect(first.count == 64)
    }

    @Test func test_hash_changes_when_title_keywords_or_content_change() throws {
        let base = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Gate",
            keywords: ["gate"],
            content: "The northern gate is sealed."
        )
        let titleChanged = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Tower",
            keywords: ["gate"],
            content: "The northern gate is sealed."
        )
        let keywordsChanged = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Gate",
            keywords: ["tower"],
            content: "The northern gate is sealed."
        )
        let contentChanged = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Gate",
            keywords: ["gate"],
            content: "The southern gate is sealed."
        )

        let baseHash = try hash(for: base)

        #expect(try hash(for: titleChanged) != baseHash)
        #expect(try hash(for: keywordsChanged) != baseHash)
        #expect(try hash(for: contentChanged) != baseHash)
    }

    @Test func test_hash_does_not_change_when_priority_or_position_change() throws {
        let base = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Gate",
            keywords: ["gate"],
            priority: 30,
            position: .beforeHistory,
            content: "The northern gate is sealed."
        )
        var changed = base
        changed.priority = 90
        changed.position = WorldBookEntryPosition.afterSystem.rawValue
        changed.isEnabled = false
        changed.updatedAt = Date(timeIntervalSince1970: 42)

        #expect(try hash(for: changed) == hash(for: base))
    }

    private func hash(for entry: WorldBookEntryRecord) throws -> String {
        try WorldBookEntryHasher.hash(
            embeddingText: WorldBookEmbeddingTextBuilder.text(for: entry),
            modelId: EmbeddingService.embeddingModelId,
            dimension: EmbeddingService.embeddingDimension
        )
    }
}
