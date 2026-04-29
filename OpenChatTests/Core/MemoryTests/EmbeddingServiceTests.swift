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

    @Test func test_tokenizer_outputs_fixed_length_ids_and_mask() throws {
        let tokenizerURL = try #require(Bundle.main.url(forResource: "tokenizer", withExtension: "json"))
        let tokenizer = try XLMRobertaTokenizer(url: tokenizerURL)

        let encoded = tokenizer.encode("query: dragon forest", maxLength: 256)

        #expect(encoded.inputIDs.count == 256)
        #expect(encoded.attentionMask.count == encoded.inputIDs.count)
        #expect(encoded.inputIDs.first == 0)

        let eosIndex = try #require(encoded.inputIDs.firstIndex(of: 2))
        #expect(eosIndex > 0)
        #expect(eosIndex < encoded.inputIDs.count - 1)

        let paddingIDs = encoded.inputIDs[(eosIndex + 1)...]
        let paddingMask = encoded.attentionMask[(eosIndex + 1)...]
        #expect(paddingIDs.allSatisfy { $0 == 1 })
        #expect(paddingMask.allSatisfy { $0 == 0 })
    }

    @Test(.timeLimit(.minutes(2))) func test_embedding_outputs_384_finite_normalized_values() throws {
        let embedding = try EmbeddingService().embed("dragon forest memory", isQuery: true)

        #expect(embedding.count == EmbeddingService.embeddingDimension)
        #expect(embedding.allSatisfy { $0.isFinite })

        let norm = sqrt(embedding.reduce(Float(0)) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.01)
    }
}
