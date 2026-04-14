import Foundation

struct TokenCounter {
    static func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var asciiCount = 0
        var cjkCount = 0
        var symbolCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                cjkCount += 1
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x20, 0x09, 0x0A:
                asciiCount += 1
            default:
                symbolCount += 1
            }
        }

        let asciiTokens = Int(ceil(Double(asciiCount) / 4.0))
        let cjkTokens = Int(ceil(Double(cjkCount) * 1.5))
        return asciiTokens + cjkTokens + symbolCount
    }

    static func count(message: ChatMessage) -> Int {
        count(message.content) + 4
    }

    static func count(message: MessageRecord) -> Int {
        count(message.content) + 4
    }
}
