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

        let skillMetadata = try CharacterSkillMarkdownMetadata(markdown: skillMarkdown)
        guard let skillName = skillMetadata.name else {
            throw CharacterSkillBundleImportError.missingSkillFrontmatterField("name")
        }
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
            ?? skillName
        let displayName = openAIYaml?.displayName
            ?? skillMetadata.firstHeading
            ?? skillName
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
                skillName: skillName,
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
            skillName: skillName,
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

private struct OpenAIYamlMetadata: Sendable {
    let snapshot: CharacterSkillYAMLSnapshot
    let json: String

    init(yaml: String) throws {
        snapshot = CharacterSkillYAMLParser.parse(yaml)
        json = try CharacterSkillBundleImportFormat.encodeJSON(snapshot)
    }

    var displayName: String? {
        snapshot.nested["interface"]?["display_name"]?.nilIfBlank
    }

    var shortDescription: String? {
        snapshot.nested["interface"]?["short_description"]?.nilIfBlank
    }
}
