import Foundation

enum WorldBookEmbeddingTextBuilder {
    static func text(for entry: WorldBookEntryRecord) throws -> String {
        let keywords = try decodedKeywords(for: entry)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return """
        Title: \(entry.title.trimmingCharacters(in: .whitespacesAndNewlines))
        Keywords: \(keywords.joined(separator: ", "))
        Content:
        \(entry.content.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private static func decodedKeywords(for entry: WorldBookEntryRecord) throws -> [String] {
        guard !entry.keywords.isEmpty else {
            return []
        }

        do {
            return try JSONDecoder().decode([String].self, from: Data(entry.keywords.utf8))
        } catch {
            throw WorldBookError.invalidKeywords(entryId: entry.id, underlying: error)
        }
    }
}
