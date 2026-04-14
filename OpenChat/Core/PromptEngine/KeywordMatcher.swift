import Foundation

struct KeywordMatcher {
    static func triggeredEntries(
        _ entries: [WorldBookEntryRecord],
        contextText: String,
        position: WorldBookEntryPosition? = nil
    ) -> [WorldBookEntryRecord] {
        entries
            .filter { $0.isEnabled }
            .filter { entry in
                guard let position else { return true }
                return entry.positionValue == position
            }
            .filter { entry in
                guard let values = try? entry.keywordValues(), !values.isEmpty else {
                    return false
                }
                return values.contains(where: { matches(keyword: $0, in: contextText) })
            }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.priority > $1.priority
            }
    }

    static func matches(keyword: String, in text: String) -> Bool {
        guard !keyword.isEmpty else {
            return false
        }

        if containsCJK(keyword) {
            return text.localizedCaseInsensitiveContains(keyword)
        }

        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = #"(?i)(?<![A-Za-z0-9])\#(escaped)(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.localizedCaseInsensitiveContains(keyword)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0x3040...0x30FF).contains(value)
                || (0xAC00...0xD7AF).contains(value)
                || (0xF900...0xFAFF).contains(value)
        }
    }
}
