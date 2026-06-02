import Foundation

enum CharacterSkillBundleImportError: LocalizedError, Sendable {
    case skillBundleStoreUnavailable
    case unsupportedImportFile
    case missingSkillMarkdown
    case multipleSkillMarkdownFiles
    case invalidSkillMarkdownEncoding
    case missingSkillFrontmatterField(String)

    var errorDescription: String? {
        switch self {
        case .skillBundleStoreUnavailable:
            String(localized: "Skill ZIP storage is unavailable.")
        case .unsupportedImportFile:
            String(localized: "Only JSON character cards and Skill ZIP bundles can be imported.")
        case .missingSkillMarkdown:
            String(localized: "Skill ZIP bundle must contain a SKILL.md file.")
        case .multipleSkillMarkdownFiles:
            String(localized: "Skill ZIP bundle contains multiple SKILL.md files.")
        case .invalidSkillMarkdownEncoding:
            String(localized: "SKILL.md must be UTF-8 text.")
        case let .missingSkillFrontmatterField(field):
            String(localized: "SKILL.md frontmatter is missing required field: \(field)")
        }
    }
}

struct CharacterSkillBundlePreparedImport: Sendable {
    var card: CharacterCardRecord
    var bundle: CharacterSkillBundleRecord
}

struct CharacterSkillBundleImportFormat {
    static func prepareImport(
        archiveData: Data,
        sourceFileName: String?,
        store: CharacterSkillBundleStore,
        now: Date = .now
    ) throws -> CharacterSkillBundlePreparedImport {
        let archiveEntries = try ZipArchiveReader().read(archiveData)
        let normalizedFiles = try normalizedSkillFiles(from: archiveEntries)
        guard let skillFile = normalizedFiles.first(where: { $0.relativePath == "SKILL.md" }) else {
            throw CharacterSkillBundleImportError.missingSkillMarkdown
        }
        guard let skillMarkdown = String(data: skillFile.data, encoding: .utf8) else {
            throw CharacterSkillBundleImportError.invalidSkillMarkdownEncoding
        }

        let skillMetadata = try SkillMarkdownMetadata(markdown: skillMarkdown)
        let openAIYaml = try openAIYamlMetadata(from: normalizedFiles)
        let cardId = UUID().uuidString
        let bundleId = UUID().uuidString
        let manifest = try store.writeImportedBundle(
            bundleId: bundleId,
            files: normalizedFiles.map {
                CharacterSkillBundleArchiveFile(relativePath: $0.relativePath, data: $0.data)
            }
        )
        let manifestJSON = try encodeJSON(manifest)
        let skillDescription = skillMetadata.description
            ?? openAIYaml?.shortDescription
            ?? skillMetadata.firstParagraph
            ?? skillMetadata.name
        let displayName = openAIYaml?.displayName
            ?? skillMetadata.firstHeading
            ?? skillMetadata.name
        let shortDescription = openAIYaml?.shortDescription
            ?? skillMetadata.scalar("short_description")
        let tags = normalizedTags([
            "skill",
            "zip",
            skillMetadata.scalar("type"),
        ])

        let card = CharacterCardRecord(
            id: cardId,
            name: displayName,
            avatar: nil,
            personality: skillDescription,
            appearance: nil,
            physique: nil,
            speechStyle: nil,
            backstory: nil,
            systemPrompt: "Use the attached role skill as the authoritative behavior guide.",
            scenario: nil,
            exampleDialogs: RecordCoders.encode([ChatMessage]()),
            creatorNotes: creatorNotes(
                skillName: skillMetadata.name,
                sourceFileName: sourceFileName,
                description: skillDescription
            ),
            tags: RecordCoders.encode(tags),
            worldBookId: nil,
            createdAt: now,
            updatedAt: now
        )
        let bundle = CharacterSkillBundleRecord(
            id: UUID().uuidString,
            characterCardId: cardId,
            sourceKind: "zip",
            sourceFileName: sourceFileName?.nilIfBlank,
            sourceArchiveSha256: SHA256Hex.hash(data: archiveData),
            bundleRelativePath: bundleId,
            skillMarkdownRelativePath: "SKILL.md",
            skillMarkdownSha256: SHA256Hex.hash(data: skillFile.data),
            skillName: skillMetadata.name,
            skillDescription: skillDescription,
            skillShortDescription: shortDescription,
            frontmatterJSON: skillMetadata.frontmatterJSON,
            agentsOpenAIYamlJSON: openAIYaml?.json,
            fileManifestJSON: manifestJSON,
            materializationMode: "fullSkillMarkdown",
            createdAt: now,
            updatedAt: now
        )
        return CharacterSkillBundlePreparedImport(card: card, bundle: bundle)
    }

    static func isZipImport(data: Data, sourceFileName: String?) -> Bool {
        if sourceFileName?.lowercased().hasSuffix(".zip") == true {
            return true
        }
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B
    }

    private static func normalizedSkillFiles(from entries: [ZipArchiveEntry]) throws -> [ZipArchiveEntry] {
        let skillCandidates = entries.filter { $0.relativePath.split(separator: "/").last == "SKILL.md" }
        guard !skillCandidates.isEmpty else {
            throw CharacterSkillBundleImportError.missingSkillMarkdown
        }
        guard skillCandidates.count == 1, let skillPath = skillCandidates.first?.relativePath else {
            throw CharacterSkillBundleImportError.multipleSkillMarkdownFiles
        }

        let rootPrefix = rootPrefix(forSkillPath: skillPath)
        var normalized: [ZipArchiveEntry] = []
        var seenPaths = Set<String>()
        for entry in entries {
            guard let strippedPath = strip(rootPrefix: rootPrefix, from: entry.relativePath),
                  !strippedPath.isEmpty
            else {
                continue
            }
            guard seenPaths.insert(strippedPath).inserted else {
                throw ZipArchiveError.duplicateFilePath(strippedPath)
            }
            normalized.append(ZipArchiveEntry(relativePath: strippedPath, data: entry.data))
        }
        return normalized.sorted { $0.relativePath < $1.relativePath }
    }

    private static func rootPrefix(forSkillPath skillPath: String) -> String {
        let components = skillPath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/") + "/"
    }

    private static func strip(rootPrefix: String, from path: String) -> String? {
        guard !rootPrefix.isEmpty else { return path }
        guard path.hasPrefix(rootPrefix) else { return nil }
        return String(path.dropFirst(rootPrefix.count))
    }

    private static func openAIYamlMetadata(from files: [ZipArchiveEntry]) throws -> OpenAIYamlMetadata? {
        guard let yamlFile = files.first(where: {
            $0.relativePath == "agents/openai.yaml" || $0.relativePath == ".agents/openai.yaml"
        }) else {
            return nil
        }
        guard let yaml = String(data: yamlFile.data, encoding: .utf8) else {
            return nil
        }
        return try OpenAIYamlMetadata(yaml: yaml)
    }

    private static func creatorNotes(
        skillName: String,
        sourceFileName: String?,
        description: String
    ) -> String {
        var lines = [
            "Imported from Skill ZIP.",
            "Skill: \(skillName)",
            "Description: \(description)",
        ]
        if let sourceFileName = sourceFileName?.nilIfBlank {
            lines.insert("Source: \(sourceFileName)", at: 1)
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizedTags(_ values: [String?]) -> [String] {
        Array(Set(values.compactMap { $0?.nilIfBlank })).sorted()
    }

    fileprivate static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private struct SkillMarkdownMetadata: Sendable {
    let frontmatter: SimpleYAMLSnapshot
    let frontmatterJSON: String
    let body: String

    init(markdown: String) throws {
        let parsed = SimpleFrontmatterParser.parse(markdown)
        frontmatter = parsed.frontmatter
        body = parsed.body
        guard parsed.frontmatter.scalars["name"]?.nilIfBlank != nil else {
            throw CharacterSkillBundleImportError.missingSkillFrontmatterField("name")
        }
        frontmatterJSON = try CharacterSkillBundleImportFormat.encodeJSON(frontmatter)
    }

    var name: String {
        scalar("name") ?? "Skill"
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

private struct OpenAIYamlMetadata: Sendable {
    let snapshot: SimpleYAMLSnapshot
    let json: String

    init(yaml: String) throws {
        snapshot = SimpleYAMLParser.parse(yaml)
        json = try CharacterSkillBundleImportFormat.encodeJSON(snapshot)
    }

    var displayName: String? {
        snapshot.nested["interface"]?["display_name"]?.nilIfBlank
    }

    var shortDescription: String? {
        snapshot.nested["interface"]?["short_description"]?.nilIfBlank
    }
}

private struct SimpleFrontmatterParser {
    static func parse(_ markdown: String) -> (frontmatter: SimpleYAMLSnapshot, body: String) {
        guard markdown.hasPrefix("---") else {
            return (SimpleYAMLSnapshot(), markdown)
        }

        let lines = markdown.components(separatedBy: .newlines)
        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (SimpleYAMLSnapshot(), markdown)
        }

        let frontmatterLines = Array(lines[1..<closingIndex])
        let bodyLines = Array(lines[(closingIndex + 1)...])
        return (
            SimpleYAMLParser.parse(lines: frontmatterLines),
            bodyLines.joined(separator: "\n")
        )
    }
}

private struct SimpleYAMLParser {
    static func parse(_ yaml: String) -> SimpleYAMLSnapshot {
        parse(lines: yaml.components(separatedBy: .newlines))
    }

    static func parse(lines: [String]) -> SimpleYAMLSnapshot {
        var snapshot = SimpleYAMLSnapshot()
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

private struct SimpleYAMLSnapshot: Codable, Sendable, Equatable {
    var scalars: [String: String] = [:]
    var nested: [String: [String: String]] = [:]
}
