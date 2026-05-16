import Foundation
import Testing

@testable import OpenChat

@Suite("WorldBookEmbeddingTextBuilder")
struct WorldBookEmbeddingTextBuilderTests {
    @Test func test_text_includes_title_keywords_and_content() throws {
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "  Silverwood  ",
            keywords: [" silverwood ", "elf"],
            content: "\n  Silver trees hide the eastern gate.  \n"
        )

        let text = try WorldBookEmbeddingTextBuilder.text(for: entry)

        #expect(text == """
        Title: Silverwood
        Keywords: silverwood, elf
        Content:
        Silver trees hide the eastern gate.
        """)
    }

    @Test func test_text_allows_empty_keywords() throws {
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-a",
            title: "Gate",
            keywords: [],
            content: "Hidden gate lore."
        )

        let text = try WorldBookEmbeddingTextBuilder.text(for: entry)

        #expect(text.contains("Keywords: "))
        #expect(text.contains("Content:\nHidden gate lore."))
    }

    @Test func test_text_invalid_keywords_throws_world_book_error() throws {
        var entry = TestHelpers.makeWorldBookEntry(worldBookId: "world-a", id: "bad-keywords")
        entry.keywords = "{not json]"

        do {
            _ = try WorldBookEmbeddingTextBuilder.text(for: entry)
            Issue.record("Expected invalid keywords to throw")
        } catch let error as WorldBookError {
            guard case .invalidKeywords(let entryId, _) = error else {
                Issue.record("Expected WorldBookError.invalidKeywords, got \(error)")
                return
            }
            #expect(entryId == "bad-keywords")
        } catch {
            Issue.record("Expected WorldBookError.invalidKeywords, got \(error)")
        }
    }
}
