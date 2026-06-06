import Foundation

struct CharacterSkillReferenceFile: Sendable, Equatable {
    let relativePath: String
    let url: URL
}

struct CharacterSkillBundleArchiveFile: Sendable, Equatable {
    let relativePath: String
    let data: Data
}

struct CharacterSkillBundleFileManifestEntry: Codable, Sendable, Equatable {
    var relativePath: String
    var byteCount: Int
    var sha256: String
}

struct CharacterSkillBundleStore: Sendable {
    let rootDirectory: URL

    static func live() throws -> CharacterSkillBundleStore {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CharacterSkillBundleError.storageDirectoryUnavailable
        }
        return CharacterSkillBundleStore(
            rootDirectory: applicationSupport
                .appending(path: "OpenChat", directoryHint: .isDirectory)
                .appending(path: "SkillBundles", directoryHint: .isDirectory)
        )
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func bundleDirectory(bundleRelativePath: String) -> URL {
        rootDirectory.appending(path: bundleRelativePath, directoryHint: .isDirectory)
    }

    func contentDirectory(bundleRelativePath: String) -> URL {
        bundleDirectory(bundleRelativePath: bundleRelativePath)
            .appending(path: "content", directoryHint: .isDirectory)
    }

    func skillMarkdownURL(for record: CharacterSkillBundleRecord) -> URL {
        contentDirectory(bundleRelativePath: record.bundleRelativePath)
            .appending(path: record.skillMarkdownRelativePath)
    }

    func prepareBundleDirectory(bundleId: String) throws -> URL {
        let bundleDirectory = bundleDirectory(bundleRelativePath: bundleId)
        do {
            try FileManager.default.createDirectory(
                at: bundleDirectory.appending(path: "content", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: bundleDirectory.appending(path: "derived", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            return bundleDirectory
        } catch {
            throw CharacterSkillBundleError.directoryCreationFailed(bundleDirectory, underlying: error)
        }
    }

    func writeImportedBundle(
        bundleId: String,
        files: [CharacterSkillBundleArchiveFile]
    ) throws -> [CharacterSkillBundleFileManifestEntry] {
        let bundleDirectory = try prepareBundleDirectory(bundleId: bundleId)
        let contentRoot = bundleDirectory.appending(path: "content", directoryHint: .isDirectory)
        var seenPaths = Set<String>()
        var manifest: [CharacterSkillBundleFileManifestEntry] = []

        do {
            for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
                let relativePath = try normalizedRelativePath(file.relativePath)
                guard seenPaths.insert(relativePath).inserted else {
                    throw CharacterSkillBundleError.duplicateFilePath(relativePath)
                }

                let destinationURL = contentRoot.appending(path: relativePath).standardizedFileURL
                guard destinationURL.path.hasPrefix(contentRoot.standardizedFileURL.path + "/") else {
                    throw CharacterSkillBundleError.unsafePath(file.relativePath)
                }
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.data.write(to: destinationURL, options: .atomic)
                manifest.append(
                    CharacterSkillBundleFileManifestEntry(
                        relativePath: relativePath,
                        byteCount: file.data.count,
                        sha256: SHA256Hex.hash(data: file.data)
                    )
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: bundleDirectory)
            if let bundleError = error as? CharacterSkillBundleError {
                throw bundleError
            }
            throw CharacterSkillBundleError.fileWriteFailed(bundleDirectory, underlying: error)
        }

        return manifest
    }

    func readSkillMarkdown(for record: CharacterSkillBundleRecord) throws -> String {
        let url = try resolvedContentFileURL(
            bundleRelativePath: record.bundleRelativePath,
            relativePath: record.skillMarkdownRelativePath
        )
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CharacterSkillBundleError.fileReadFailed(url, underlying: error)
        }
    }

    func writeSkillMarkdown(
        _ markdown: String,
        for record: CharacterSkillBundleRecord
    ) throws -> CharacterSkillBundleFileManifestEntry {
        try writeContentFile(
            Data(markdown.utf8),
            bundleRelativePath: record.bundleRelativePath,
            relativePath: record.skillMarkdownRelativePath
        )
    }

    func referenceMarkdownFiles(for record: CharacterSkillBundleRecord) throws -> [CharacterSkillReferenceFile] {
        let contentRoot = try resolvedContentRoot(bundleRelativePath: record.bundleRelativePath)
        let referencesRoot = try resolvedContentDirectory(
            bundleRelativePath: record.bundleRelativePath,
            relativePath: "references"
        )
        guard FileManager.default.fileExists(atPath: referencesRoot.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: referencesRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [CharacterSkillReferenceFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  url.pathExtension.lowercased() == "md"
            else {
                continue
            }

            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path.hasPrefix(contentRoot.path + "/") else {
                throw CharacterSkillBundleError.unsafePath(url.path)
            }
            let relativePath = String(standardizedURL.path.dropFirst(contentRoot.path.count + 1))
            files.append(CharacterSkillReferenceFile(relativePath: relativePath, url: standardizedURL))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    func readReferenceMarkdown(for record: CharacterSkillBundleRecord, relativePath: String) throws -> String {
        let url = try resolvedContentFileURL(
            bundleRelativePath: record.bundleRelativePath,
            relativePath: relativePath
        )
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CharacterSkillBundleError.fileReadFailed(url, underlying: error)
        }
    }

    func writeReferenceMarkdown(
        _ markdown: String,
        for record: CharacterSkillBundleRecord,
        relativePath: String
    ) throws -> CharacterSkillBundleFileManifestEntry {
        let normalizedPath = try normalizedRelativePath(relativePath)
        guard normalizedPath.hasPrefix("references/"),
              normalizedPath.lowercased().hasSuffix(".md")
        else {
            throw CharacterSkillBundleError.unsafePath(relativePath)
        }
        return try writeContentFile(
            Data(markdown.utf8),
            bundleRelativePath: record.bundleRelativePath,
            relativePath: normalizedPath
        )
    }

    func contentFileManifestEntries(
        for record: CharacterSkillBundleRecord
    ) throws -> [CharacterSkillBundleFileManifestEntry] {
        let contentRoot = try resolvedContentRoot(bundleRelativePath: record.bundleRelativePath)
        guard FileManager.default.fileExists(atPath: contentRoot.path),
              let enumerator = FileManager.default.enumerator(
                at: contentRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else {
            return []
        }

        var manifest: [CharacterSkillBundleFileManifestEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                continue
            }

            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path.hasPrefix(contentRoot.path + "/") else {
                throw CharacterSkillBundleError.unsafePath(url.path)
            }
            let relativePath = String(standardizedURL.path.dropFirst(contentRoot.path.count + 1))
            let data = try Data(contentsOf: standardizedURL)
            manifest.append(
                CharacterSkillBundleFileManifestEntry(
                    relativePath: relativePath,
                    byteCount: data.count,
                    sha256: SHA256Hex.hash(data: data)
                )
            )
        }
        return manifest.sorted { $0.relativePath < $1.relativePath }
    }

    func deleteBundle(_ record: CharacterSkillBundleRecord) throws {
        let url = try resolvedBundleDirectory(bundleRelativePath: record.bundleRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw CharacterSkillBundleError.fileWriteFailed(url, underlying: error)
        }
    }

    func duplicateBundle(
        _ record: CharacterSkillBundleRecord,
        characterCardId: String,
        now: Date = .now
    ) throws -> CharacterSkillBundleRecord {
        let newBundleId = UUID().uuidString
        let sourceURL = try resolvedBundleDirectory(bundleRelativePath: record.bundleRelativePath)
        let destinationURL = try resolvedBundleDirectory(bundleRelativePath: newBundleId)
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw CharacterSkillBundleError.fileWriteFailed(destinationURL, underlying: error)
        }

        return CharacterSkillBundleRecord(
            id: UUID().uuidString,
            characterCardId: characterCardId,
            sourceKind: record.sourceKind,
            sourceFileName: record.sourceFileName,
            sourceArchiveSha256: record.sourceArchiveSha256,
            bundleRelativePath: newBundleId,
            skillMarkdownRelativePath: record.skillMarkdownRelativePath,
            skillMarkdownSha256: record.skillMarkdownSha256,
            skillName: record.skillName,
            skillDescription: record.skillDescription,
            skillShortDescription: record.skillShortDescription,
            frontmatterJSON: record.frontmatterJSON,
            agentsOpenAIYamlJSON: record.agentsOpenAIYamlJSON,
            fileManifestJSON: record.fileManifestJSON,
            materializationMode: record.materializationMode,
            createdAt: now,
            updatedAt: now
        )
    }

    private func resolvedBundleDirectory(bundleRelativePath: String) throws -> URL {
        let relativePath = try normalizedRelativePath(bundleRelativePath)
        let url = rootDirectory.appending(path: relativePath, directoryHint: .isDirectory).standardizedFileURL
        guard url.path.hasPrefix(rootDirectory.standardizedFileURL.path) else {
            throw CharacterSkillBundleError.unsafePath(bundleRelativePath)
        }
        return url
    }

    private func resolvedContentFileURL(bundleRelativePath: String, relativePath: String) throws -> URL {
        let filePath = try normalizedRelativePath(relativePath)
        let contentRoot = try resolvedContentRoot(bundleRelativePath: bundleRelativePath)
        let url = contentRoot.appending(path: filePath).standardizedFileURL
        guard url.path.hasPrefix(contentRoot.path) else {
            throw CharacterSkillBundleError.unsafePath(relativePath)
        }
        return url
    }

    private func resolvedContentDirectory(bundleRelativePath: String, relativePath: String) throws -> URL {
        let directoryPath = try normalizedRelativePath(relativePath)
        let contentRoot = try resolvedContentRoot(bundleRelativePath: bundleRelativePath)
        let url = contentRoot.appending(path: directoryPath, directoryHint: .isDirectory).standardizedFileURL
        guard url.path.hasPrefix(contentRoot.path) else {
            throw CharacterSkillBundleError.unsafePath(relativePath)
        }
        return url
    }

    private func resolvedContentRoot(bundleRelativePath: String) throws -> URL {
        let bundlePath = try normalizedRelativePath(bundleRelativePath)
        let contentRoot = rootDirectory
            .appending(path: bundlePath, directoryHint: .isDirectory)
            .appending(path: "content", directoryHint: .isDirectory)
            .standardizedFileURL
        guard contentRoot.path.hasPrefix(rootDirectory.standardizedFileURL.path) else {
            throw CharacterSkillBundleError.unsafePath(bundleRelativePath)
        }
        return contentRoot
    }

    private func writeContentFile(
        _ data: Data,
        bundleRelativePath: String,
        relativePath: String
    ) throws -> CharacterSkillBundleFileManifestEntry {
        let filePath = try normalizedRelativePath(relativePath)
        let contentRoot = try resolvedContentRoot(bundleRelativePath: bundleRelativePath)
        let destinationURL = contentRoot.appending(path: filePath).standardizedFileURL
        guard destinationURL.path.hasPrefix(contentRoot.path + "/") else {
            throw CharacterSkillBundleError.unsafePath(relativePath)
        }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
            return CharacterSkillBundleFileManifestEntry(
                relativePath: filePath,
                byteCount: data.count,
                sha256: SHA256Hex.hash(data: data)
            )
        } catch {
            throw CharacterSkillBundleError.fileWriteFailed(destinationURL, underlying: error)
        }
    }

    private func normalizedRelativePath(_ rawPath: String) throws -> String {
        let components = rawPath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !rawPath.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw CharacterSkillBundleError.unsafePath(rawPath)
        }
        return components.joined(separator: "/")
    }
}
