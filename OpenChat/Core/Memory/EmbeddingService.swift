import CoreML
import Foundation

final class EmbeddingService: @unchecked Sendable {
    static let embeddingDimension = 384
    private static let maxTokenLength = 512

    private let lock = NSLock()
    private var model: MLModel?
    private var tokenizer: XLMRobertaTokenizer?

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        let prefixed = isQuery ? "query: \(text)" : "passage: \(text)"
        let tokenizer = try loadTokenizer()
        let encoded = tokenizer.encode(prefixed, maxLength: Self.maxTokenLength)

        let model = try loadModel()
        let inputIDs = try MLMultiArray(shape: [1, encoded.inputIDs.count as NSNumber], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, encoded.attentionMask.count as NSNumber], dataType: .int32)

        for (i, id) in encoded.inputIDs.enumerated() {
            inputIDs[[0, i as NSNumber]] = NSNumber(value: id)
        }
        for (i, mask) in encoded.attentionMask.enumerated() {
            attentionMask[[0, i as NSNumber]] = NSNumber(value: mask)
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

        let count = embeddingsArray.count
        var embedding = [Float](repeating: 0, count: count)
        let ptr = embeddingsArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            embedding[i] = ptr[i]
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
            config.computeUnits = .cpuAndGPU
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

    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

// MARK: - XLMRobertaTokenizer

struct XLMRobertaTokenizer: Sendable {
    private let vocab: [String: Int]
    private let merges: [(String, String)]
    private let bosTokenID: Int32
    private let eosTokenID: Int32
    private let padTokenID: Int32
    private let unkTokenID: Int32

    struct EncodedInput: Sendable {
        let inputIDs: [Int32]
        let attentionMask: [Int32]
    }

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let model = json["model"] as? [String: Any] ?? [:]
        let vocabList = model["vocab"] as? [String: Int] ?? [:]
        self.vocab = vocabList

        let mergeStrings = model["merges"] as? [String] ?? []
        self.merges = mergeStrings.compactMap { merge in
            let parts = merge.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }

        self.bosTokenID = 0   // <s>
        self.eosTokenID = 2   // </s>
        self.padTokenID = 1   // <pad>
        self.unkTokenID = 3   // <unk>
    }

    func encode(_ text: String, maxLength: Int) -> EncodedInput {
        let tokens = tokenize(text)
        let tokenIDs = tokens.map { vocab[$0] ?? Int(unkTokenID) }

        // Truncate to maxLength - 2 (for BOS/EOS)
        let maxContentLength = maxLength - 2
        let truncated = Array(tokenIDs.prefix(maxContentLength))

        var inputIDs: [Int32] = [bosTokenID]
        inputIDs.append(contentsOf: truncated.map { Int32($0) })
        inputIDs.append(eosTokenID)

        let attentionMask = [Int32](repeating: 1, count: inputIDs.count)
        return EncodedInput(inputIDs: inputIDs, attentionMask: attentionMask)
    }

    private func tokenize(_ text: String) -> [String] {
        // SentencePiece-style: split into words by spaces, prefix with ▁
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var allTokens: [String] = []

        for (index, word) in words.enumerated() {
            let prefix = index == 0 ? "▁" : "▁"
            let prefixed = prefix + word
            let subTokens = bpe(prefixed)
            allTokens.append(contentsOf: subTokens)
        }

        return allTokens
    }

    private func bpe(_ word: String) -> [String] {
        var symbols = word.map { String($0) }
        guard symbols.count > 1 else { return symbols }

        // Build merge priority lookup
        var mergeRank: [String: Int] = [:]
        for (i, (a, b)) in merges.enumerated() {
            mergeRank["\(a) \(b)"] = i
        }

        while symbols.count > 1 {
            var bestPair: (Int, String)?
            for i in 0..<(symbols.count - 1) {
                let key = "\(symbols[i]) \(symbols[i + 1])"
                if let rank = mergeRank[key] {
                    if bestPair == nil || rank < bestPair!.0 {
                        bestPair = (rank, key)
                    }
                }
            }

            guard let (_, pair) = bestPair else { break }
            let parts = pair.split(separator: " ", maxSplits: 1)
            let first = String(parts[0])
            let second = String(parts[1])
            let merged = first + second

            var newSymbols: [String] = []
            var i = 0
            while i < symbols.count {
                if i < symbols.count - 1 && symbols[i] == first && symbols[i + 1] == second {
                    newSymbols.append(merged)
                    i += 2
                } else {
                    newSymbols.append(symbols[i])
                    i += 1
                }
            }
            symbols = newSymbols
        }

        return symbols
    }
}
