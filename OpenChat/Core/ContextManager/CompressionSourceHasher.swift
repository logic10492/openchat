import CryptoKit
import Foundation

enum CompressionSourceHasher {
    static func hash(previousSourceHash: String? = nil, messages: [MessageRecord]) -> String {
        var lines: [String] = []
        if let previousSourceHash {
            lines.append("previous:\(previousSourceHash)")
        }
        for message in messages {
            lines.append("\(message.sortOrder)\t\(message.role)\t\(message.content)")
        }
        let payload = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
