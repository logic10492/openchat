import Testing

@testable import OpenChat

@Suite("Keyword matcher")
struct KeywordMatcherTests {
    @Test func test_english_keyword_matches_word_boundaries() {
        let book = TestHelpers.makeWorldBook()
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: book.id, keywords: ["dragon"], content: "Dragons rule the sky.")

        #expect(KeywordMatcher.matches(keyword: "dragon", in: "The dragon appears."))
        #expect(!KeywordMatcher.matches(keyword: "dragon", in: "dragonfly"))
        #expect(KeywordMatcher.triggeredEntries([entry], contextText: "A dragon appears", position: .beforeHistory).count == 1)
    }

    @Test func test_cjk_keyword_matches_substring() {
        let book = TestHelpers.makeWorldBook()
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: book.id, keywords: ["精灵"], content: "精灵在森林里。")

        #expect(KeywordMatcher.matches(keyword: "精灵", in: "森林里的精灵"))
        #expect(KeywordMatcher.triggeredEntries([entry], contextText: "森林里的精灵", position: .beforeHistory).count == 1)
    }
}
