import CoreML
import Foundation
import Testing

@testable import OpenChat

private enum EmbeddingTestResources {
    static var areBundled: Bool {
        Bundle.main.url(forResource: "MultilingualE5Small", withExtension: "mlmodelc") != nil &&
            Bundle.main.url(forResource: "tokenizer", withExtension: "json") != nil
    }
}

@Suite("EmbeddingService")
struct EmbeddingServiceTests {
    @Test(.enabled(if: EmbeddingTestResources.areBundled)) func test_model_and_tokenizer_are_bundled() throws {
        let modelURL = try #require(Bundle.main.url(forResource: "MultilingualE5Small", withExtension: "mlmodelc"))
        let tokenizerURL = try #require(Bundle.main.url(forResource: "tokenizer", withExtension: "json"))

        #expect(modelURL.lastPathComponent == "MultilingualE5Small.mlmodelc")
        #expect(tokenizerURL.lastPathComponent == "tokenizer.json")
    }

    @Test(.enabled(if: EmbeddingTestResources.areBundled)) func test_tokenizer_outputs_fixed_length_ids_and_mask() throws {
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

    @Test(.enabled(if: EmbeddingTestResources.areBundled)) func test_tokenizer_applies_compatibility_normalization() throws {
        let tokenizerURL = try #require(Bundle.main.url(forResource: "tokenizer", withExtension: "json"))
        let tokenizer = try XLMRobertaTokenizer(url: tokenizerURL)

        let encoded = tokenizer.encode("①  Ⅳ", maxLength: 16)
        let eosIndex = try #require(encoded.inputIDs.firstIndex(of: 2))
        let contentIDs = encoded.inputIDs[..<eosIndex]

        #expect(contentIDs.contains(106)) // "▁1"
        #expect(contentIDs.contains(7_610)) // "▁IV"
        #expect(!contentIDs.contains(3)) // "<unk>"
    }

    @Test(.enabled(if: EmbeddingTestResources.areBundled), .timeLimit(.minutes(2))) func test_embedding_outputs_384_finite_normalized_values() throws {
        let embedding = try EmbeddingService().embed("dragon forest memory", isQuery: true)

        #expect(embedding.count == EmbeddingService.embeddingDimension)
        #expect(embedding.allSatisfy { $0.isFinite })

        let norm = sqrt(embedding.reduce(Float(0)) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.01)
    }
}
