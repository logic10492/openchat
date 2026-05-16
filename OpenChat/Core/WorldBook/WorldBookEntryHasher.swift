import CryptoKit
import Foundation

enum WorldBookEntryHasher {
    static func hash(embeddingText: String, modelId: String, dimension: Int) -> String {
        let payload = """
        model:\(modelId)
        dimension:\(dimension)
        text:
        \(embeddingText)
        """
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
