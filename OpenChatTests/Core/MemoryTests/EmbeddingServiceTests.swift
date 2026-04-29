import CoreML
import Foundation
import Testing

@testable import OpenChat

@Suite("EmbeddingService")
struct EmbeddingServiceTests {
    @Test func test_model_and_tokenizer_are_bundled() throws {
        let modelURL = try #require(Bundle.main.url(forResource: "MultilingualE5Small", withExtension: "mlmodelc"))
        let tokenizerURL = try #require(Bundle.main.url(forResource: "tokenizer", withExtension: "json"))

        #expect(modelURL.lastPathComponent == "MultilingualE5Small.mlmodelc")
        #expect(tokenizerURL.lastPathComponent == "tokenizer.json")
    }
}
