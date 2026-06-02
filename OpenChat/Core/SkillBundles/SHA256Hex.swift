import CryptoKit
import Foundation

enum SHA256Hex {
    static func hash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(text: String) -> String {
        hash(data: Data(text.utf8))
    }
}
