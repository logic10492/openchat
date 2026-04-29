import Foundation

struct XLMRobertaTokenizer: Sendable {
    private struct Piece: Sendable {
        let id: Int32
        let score: Double
    }

    struct EncodedInput: Sendable {
        let inputIDs: [Int32]
        let attentionMask: [Int32]
    }

    private let vocab: [String: Piece]
    private let maxPieceLength: Int
    private let bosTokenID: Int32
    private let eosTokenID: Int32
    private let padTokenID: Int32
    private let unkTokenID: Int32

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let model = json["model"] as? [String: Any] ?? [:]
        let vocabArray = model["vocab"] as? [[Any]] ?? []

        var entries: [String: Piece] = [:]
        var longest = 1
        for (index, row) in vocabArray.enumerated() {
            guard row.count >= 2,
                  let token = row[0] as? String,
                  let score = row[1] as? Double else {
                continue
            }
            entries[token] = Piece(id: Int32(index), score: score)
            longest = max(longest, token.count)
        }

        self.vocab = entries
        self.maxPieceLength = longest
        self.bosTokenID = entries["<s>"]?.id ?? 0
        self.padTokenID = entries["<pad>"]?.id ?? 1
        self.eosTokenID = entries["</s>"]?.id ?? 2
        self.unkTokenID = entries["<unk>"]?.id ?? 3
    }

    func encode(_ text: String, maxLength: Int) -> EncodedInput {
        guard maxLength > 0 else {
            return EncodedInput(inputIDs: [], attentionMask: [])
        }

        let maxContentLength = max(maxLength - 2, 0)
        let tokenIDs = tokenize(text).prefix(maxContentLength)

        var inputIDs: [Int32] = []
        inputIDs.append(bosTokenID)
        inputIDs.append(contentsOf: tokenIDs)
        if inputIDs.count < maxLength {
            inputIDs.append(eosTokenID)
        }

        var attentionMask = [Int32](repeating: 1, count: inputIDs.count)
        if inputIDs.count < maxLength {
            let paddingCount = maxLength - inputIDs.count
            inputIDs.append(contentsOf: repeatElement(padTokenID, count: paddingCount))
            attentionMask.append(contentsOf: repeatElement(Int32(0), count: paddingCount))
        }

        return EncodedInput(
            inputIDs: Array(inputIDs.prefix(maxLength)),
            attentionMask: Array(attentionMask.prefix(maxLength))
        )
    }

    private func tokenize(_ text: String) -> [Int32] {
        let prepared = prepareForMetaspace(text)
        return bestPathIDs(in: prepared)
    }

    private func prepareForMetaspace(_ text: String) -> String {
        let normalized = (text as NSString).precomposedStringWithCompatibilityMapping
        let collapsed = normalized
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        return "▁" + collapsed.replacingOccurrences(of: " ", with: "▁")
    }

    private func bestPathIDs(in text: String) -> [Int32] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        var bestScore = Array(repeating: -Double.infinity, count: characters.count + 1)
        var backPointer = Array(repeating: (start: 0, id: unkTokenID), count: characters.count + 1)
        bestScore[0] = 0

        for start in 0..<characters.count where bestScore[start].isFinite {
            let maxEnd = min(characters.count, start + maxPieceLength)
            var matched = false

            if start < maxEnd {
                for end in (start + 1)...maxEnd {
                    let token = String(characters[start..<end])
                    guard let piece = vocab[token] else { continue }
                    matched = true
                    let candidate = bestScore[start] + piece.score
                    if candidate > bestScore[end] {
                        bestScore[end] = candidate
                        backPointer[end] = (start, piece.id)
                    }
                }
            }

            if !matched {
                let end = start + 1
                let candidate = bestScore[start] - 100
                if candidate > bestScore[end] {
                    bestScore[end] = candidate
                    backPointer[end] = (start, unkTokenID)
                }
            }
        }

        var ids: [Int32] = []
        var index = characters.count
        while index > 0 {
            let pointer = backPointer[index]
            ids.append(pointer.id)
            index = pointer.start
        }

        return ids.reversed()
    }
}
