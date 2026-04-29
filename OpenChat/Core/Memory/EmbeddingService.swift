import CoreML
import Foundation

final class EmbeddingService: @unchecked Sendable {
    static let embeddingDimension = 384
    private static let modelInputLength = 256

    private let lock = NSLock()
    private var model: MLModel?
    private var tokenizer: XLMRobertaTokenizer?

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        let prefixed = isQuery ? "query: \(text)" : "passage: \(text)"
        let tokenizer = try loadTokenizer()
        let encoded = tokenizer.encode(prefixed, maxLength: Self.modelInputLength)

        let model = try loadModel()
        let inputIDs = try MLMultiArray(shape: [1, Self.modelInputLength as NSNumber], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, Self.modelInputLength as NSNumber], dataType: .int32)

        for index in 0..<Self.modelInputLength {
            inputIDs[[0, index as NSNumber]] = NSNumber(value: encoded.inputIDs[index])
            attentionMask[[0, index as NSNumber]] = NSNumber(value: encoded.attentionMask[index])
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])

        let result = try model.prediction(from: provider)
        guard let embeddingsValue = result.featureValue(for: "embeddings"),
              let embeddingsArray = embeddingsValue.multiArrayValue else {
            throw MemoryError.embeddingFailed(underlying: MemoryError.invalidExtractionResponse)
        }

        let embedding = try readEmbedding(embeddingsArray)
        guard embedding.count == Self.embeddingDimension else {
            throw MemoryError.embeddingFailed(
                underlying: NSError(
                    domain: "EmbeddingService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected embedding dimension \(embedding.count)"]
                )
            )
        }

        return normalize(embedding)
    }

    private func loadModel() throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        if let model { return model }
        guard let url = Bundle.main.url(forResource: "MultilingualE5Small", withExtension: "mlmodelc") else {
            throw MemoryError.modelLoadFailed(
                underlying: NSError(domain: "EmbeddingService", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Model file not found in bundle"])
            )
        }
        do {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
            #else
            config.computeUnits = .cpuAndGPU
            #endif
            let loaded = try MLModel(contentsOf: url, configuration: config)
            model = loaded
            return loaded
        } catch {
            throw MemoryError.modelLoadFailed(underlying: error)
        }
    }

    private func loadTokenizer() throws -> XLMRobertaTokenizer {
        lock.lock()
        defer { lock.unlock() }
        if let tokenizer { return tokenizer }
        guard let url = Bundle.main.url(forResource: "tokenizer", withExtension: "json") else {
            throw MemoryError.modelLoadFailed(
                underlying: NSError(domain: "EmbeddingService", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Tokenizer file not found in bundle"])
            )
        }
        do {
            let loaded = try XLMRobertaTokenizer(url: url)
            tokenizer = loaded
            return loaded
        } catch {
            throw MemoryError.modelLoadFailed(underlying: error)
        }
    }

    private func readEmbedding(_ array: MLMultiArray) throws -> [Float] {
        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            return (0..<array.count).map { Float(pointer[$0]) }
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return (0..<array.count).map { pointer[$0] }
        default:
            throw MemoryError.embeddingFailed(
                underlying: NSError(
                    domain: "EmbeddingService",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported embedding output type \(array.dataType.rawValue)"]
                )
            )
        }
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
