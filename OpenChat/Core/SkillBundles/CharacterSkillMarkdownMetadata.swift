import Foundation

struct CharacterSkillMarkdownMetadata: Sendable {
    let frontmatter: CharacterSkillYAMLSnapshot
    let frontmatterJSON: String
    let body: String

    init(markdown: String) throws {
        let parsed = CharacterSkillFrontmatterParser.parse(markdown)
        frontmatter = parsed.frontmatter
        body = parsed.body
        frontmatterJSON = try CharacterSkillJSONCoder.encodeJSON(parsed.frontmatter)
    }

    var name: String? {
        scalar("name")
    }

    var description: String? {
        scalar("description")
    }

    var firstHeading: String? {
        body
            .components(separatedBy: .newlines)
            .lazy
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return nil }
                return trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    .nilIfBlank
            }
            .first
    }

    var firstParagraph: String? {
        body
            .components(separatedBy: "\n\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func scalar(_ key: String) -> String? {
        frontmatter.scalars[key]?.nilIfBlank
    }
}

enum CharacterSkillJSONCoder {
    static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

enum CharacterSkillFrontmatterParser {
    static func parse(_ markdown: String) -> (frontmatter: CharacterSkillYAMLSnapshot, body: String) {
        guard markdown.hasPrefix("---") else {
            return (CharacterSkillYAMLSnapshot(), markdown)
        }

        let lines = markdown.components(separatedBy: .newlines)
        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (CharacterSkillYAMLSnapshot(), markdown)
        }

        let frontmatterLines = Array(lines[1..<closingIndex])
        let bodyLines = Array(lines[(closingIndex + 1)...])
        return (
            CharacterSkillYAMLParser.parse(lines: frontmatterLines),
            bodyLines.joined(separator: "\n")
        )
    }
}

enum CharacterSkillYAMLParser {
    static func parse(_ yaml: String) -> CharacterSkillYAMLSnapshot {
        parse(lines: yaml.components(separatedBy: .newlines))
    }

    static func parse(lines: [String]) -> CharacterSkillYAMLSnapshot {
        var snapshot = CharacterSkillYAMLSnapshot()
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !line.hasPrefix(" ") else {
                index += 1
                continue
            }
            guard let separator = line.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if isBlockScalar(rawValue) {
                let parsedBlock = parseBlock(lines: lines, startIndex: index + 1, folded: rawValue.hasPrefix(">"))
                snapshot.scalars[key] = parsedBlock.value.nilIfBlank
                index = parsedBlock.nextIndex
            } else if rawValue.isEmpty {
                let parsedNested = parseNested(lines: lines, startIndex: index + 1)
                if !parsedNested.values.isEmpty {
                    snapshot.nested[key] = parsedNested.values
                }
                index = parsedNested.nextIndex
            } else {
                snapshot.scalars[key] = unquoted(rawValue).nilIfBlank
                index += 1
            }
        }

        return snapshot
    }

    private static func parseBlock(
        lines: [String],
        startIndex: Int,
        folded: Bool
    ) -> (value: String, nextIndex: Int) {
        var values: [String] = []
        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                break
            }
            values.append(stripIndent(line))
            index += 1
        }
        return (
            folded ? values.joined(separator: " ") : values.joined(separator: "\n"),
            index
        )
    }

    private static func parseNested(
        lines: [String],
        startIndex: Int
    ) -> (values: [String: String], nextIndex: Int) {
        var values: [String: String] = [:]
        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard line.hasPrefix(" ") || line.hasPrefix("\t") else {
                break
            }
            let nestedLine = stripIndent(line)
            if let separator = nestedLine.firstIndex(of: ":") {
                let key = String(nestedLine[..<separator]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(nestedLine[nestedLine.index(after: separator)...])
                    .trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, let value = unquoted(rawValue).nilIfBlank {
                    values[key] = value
                }
            }
            index += 1
        }
        return (values, index)
    }

    private static func isBlockScalar(_ rawValue: String) -> Bool {
        rawValue.hasPrefix("|") || rawValue.hasPrefix(">")
    }

    private static func stripIndent(_ line: String) -> String {
        var stripped = line
        while stripped.first == " " || stripped.first == "\t" {
            stripped.removeFirst()
        }
        return stripped
    }

    private static func unquoted(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

struct CharacterSkillYAMLSnapshot: Codable, Sendable, Equatable {
    var scalars: [String: String] = [:]
    var nested: [String: [String: String]] = [:]
}
