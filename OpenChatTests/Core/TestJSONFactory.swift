import Foundation

enum TestJSONFactory {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func encodedString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
