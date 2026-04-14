import Foundation

struct WorldBookImportFormat {
    struct ParsedEntry: Identifiable, Sendable {
        let id = UUID()
        var title: String
        var keywords: [String]
        var content: String
        var priority: Int
        var position: String
        var warnings: [String]
    }

    static let formatGuide = """
    ## Entry Title
    - keywords: alpha, beta
    - priority: 80
    - position: before_history

    Entry content goes here.
    """

    static func parse(text: String) -> [ParsedEntry] {
        let sections = text.components(separatedBy: "\n## ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return sections.compactMap { section in
            let normalized = section.hasPrefix("## ") ? String(section.dropFirst(3)) : section
            let lines = normalized.components(separatedBy: .newlines)
            guard let title = lines.first?.nilIfBlank else { return nil }
            var keywords: [String] = []
            var priority = 50
            var position = "before_history"
            var contentLines: [String] = []
            var warnings: [String] = []

            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- keywords:") {
                    keywords = trimmed
                        .replacingOccurrences(of: "- keywords:", with: "")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                } else if trimmed.hasPrefix("- priority:") {
                    priority = Int(trimmed.replacingOccurrences(of: "- priority:", with: "").trimmingCharacters(in: .whitespaces)) ?? 50
                } else if trimmed.hasPrefix("- position:") {
                    position = trimmed.replacingOccurrences(of: "- position:", with: "").trimmingCharacters(in: .whitespaces)
                } else if !trimmed.isEmpty {
                    contentLines.append(line)
                }
            }

            if keywords.isEmpty {
                keywords = [title]
                warnings.append(String(localized: "Missing keywords, title used as fallback."))
            }

            return ParsedEntry(
                title: title,
                keywords: keywords,
                content: contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                priority: priority,
                position: position,
                warnings: warnings
            )
        }
    }
}
