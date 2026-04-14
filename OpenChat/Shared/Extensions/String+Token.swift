import Foundation

extension String {
    var approximatedTokenCount: Int {
        TokenCounter.count(self)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
