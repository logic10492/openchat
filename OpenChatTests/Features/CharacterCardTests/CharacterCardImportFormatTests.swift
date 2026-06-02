import Foundation
import Testing
import zlib

@testable import OpenChat

@MainActor
@Suite("Character card import")
struct CharacterCardImportFormatTests {
    @Test func test_parse_openchat_format_maps_all_fields() throws {
        let parsed = try CharacterCardImportFormat.parse(text: """
        {
          "formatVersion": 1,
          "type": "openchat_character_card",
          "data": {
            "name": "Mira",
            "personality": "Careful.",
            "appearance": "Silver hair.",
            "physique": "Lean.",
            "speechStyle": "Quiet.",
            "backstory": "From the old district.",
            "systemPrompt": "Stay in character.",
            "scenario": "Rainy street.",
            "exampleDialogs": [
              {"role": "user", "content": "Hello"},
              {"role": "assistant", "content": "Stay close."}
            ],
            "creatorNotes": "Test card.",
            "tags": ["test", "noir"]
          }
        }
        """)

        #expect(parsed.name == "Mira")
        #expect(parsed.personality == "Careful.")
        #expect(parsed.appearance == "Silver hair.")
        #expect(parsed.physique == "Lean.")
        #expect(parsed.speechStyle == "Quiet.")
        #expect(parsed.backstory == "From the old district.")
        #expect(parsed.systemPrompt == "Stay in character.")
        #expect(parsed.scenario == "Rainy street.")
        #expect(parsed.exampleDialogs.count == 2)
        #expect(parsed.tags == ["noir", "test"])
        #expect(parsed.creatorNotes == "Test card.")
    }

    @Test func test_parse_sillytavern_v2_is_unsupported() {
        #expect(throws: CharacterCardImportError.unsupportedFormat) {
            _ = try CharacterCardImportFormat.parse(text: """
        {
          "spec": "chara_card_v2",
          "spec_version": "2.0",
          "data": {
            "name": "Shiroko",
            "description": "A student moving through a ruined city.",
            "personality": "Quiet, direct, protective.",
            "scenario": "A night patrol.",
            "first_mes": "Stay behind me.",
            "mes_example": "<START>\\n{{user}}: Are you afraid?\\n{{char}}: Fear is data. I still move.\\n",
            "system_prompt": "Use restrained horror.",
            "creator_notes": "Imported from ST.",
            "tags": ["Blue Archive", "horror", "horror"]
          }
        }
        """)
        }
    }

    @Test func test_import_card_persists_record_and_refreshes_list() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let viewModel = CharacterCardListViewModel(
            databaseManager: manager,
            appState: AppState()
        )
        let parsed = CharacterCardImportFormat.ParsedCard(
            name: "Imported Shiroko",
            personality: "Quiet and alert.",
            appearance: nil,
            physique: nil,
            speechStyle: "Short sentences.",
            backstory: nil,
            systemPrompt: nil,
            scenario: "A ruined subway platform.",
            exampleDialogs: [ChatMessage(role: "assistant", content: "Keep moving.")],
            creatorNotes: nil,
            tags: ["BA", "horror"],
            warnings: []
        )

        let saved = try await viewModel.importCard(parsed)

        let fetched = try #require(try await manager.fetchCharacterCard(id: saved.id))
        #expect(fetched.name == "Imported Shiroko")
        #expect(fetched.personality == "Quiet and alert.")
        #expect(fetched.speechStyle == "Short sentences.")
        #expect(fetched.scenario == "A ruined subway platform.")
        #expect(fetched.decodedExampleDialogs == [ChatMessage(role: "assistant", content: "Keep moving.")])
        #expect(fetched.decodedTags == ["BA", "horror"])
        #expect(viewModel.cards.map(\.id) == [saved.id])
    }

    @Test func test_parse_missing_name_throws() {
        #expect(throws: CharacterCardImportError.missingName) {
            _ = try CharacterCardImportFormat.parse(text: """
            {
              "formatVersion": 1,
              "type": "openchat_character_card",
              "data": {
                "name": "   "
              }
            }
            """)
        }
    }

    @Test func test_zip_reader_inflates_deflated_entries() throws {
        let skillMarkdown = """
        ---
        name: shiroko-perspective
        description: Test role skill.
        ---

        # Shiroko
        """
        let archive = try makeZipArchive(entries: [
            ZipTestEntry(
                path: "Shiroko/SKILL.md",
                data: Data(skillMarkdown.utf8),
                compression: .deflated
            ),
        ])

        let entries = try ZipArchiveReader().read(archive)

        let entry = try #require(entries.first)
        #expect(entry.relativePath == "Shiroko/SKILL.md")
        #expect(String(data: entry.data, encoding: .utf8) == skillMarkdown)
    }

    @Test func test_zip_reader_rejects_path_traversal() throws {
        let archive = try makeZipArchive(entries: [
            ZipTestEntry(
                path: "../SKILL.md",
                data: Data("unsafe".utf8),
                compression: .stored
            ),
        ])

        do {
            _ = try ZipArchiveReader().read(archive)
            Issue.record("Expected unsafe zip path to throw")
        } catch let error as ZipArchiveError {
            guard case .unsafePath("../SKILL.md") = error else {
                Issue.record("Expected unsafePath, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected ZipArchiveError.unsafePath, got \(error)")
        }
    }

    @Test func test_import_skill_zip_creates_card_bundle_and_runtime_material() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "OpenChatCharacterSkillZipImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let store = CharacterSkillBundleStore(rootDirectory: rootDirectory)
        let viewModel = CharacterCardListViewModel(
            databaseManager: manager,
            appState: AppState(),
            skillBundleStore: store
        )
        let skillMarkdown = """
        ---
        name: shiroko-perspective
        description: |
          Quiet tactical role skill.
          Uses local references before answering factual questions.
        type: perspective
        ---

        # Shiroko Role

        Stay concise and check references when asked about equipment.
        """
        let openAIYaml = """
        interface:
          display_name: "Shiroko Role"
          short_description: "Quiet tactical role skill"
        """
        let referenceMarkdown = """
        # Equipment Notes

        Cycling equipment and fallback route planning are important.
        """
        let archive = try makeZipArchive(entries: [
            ZipTestEntry(
                path: "shiroko-role/SKILL.md",
                data: Data(skillMarkdown.utf8),
                compression: .deflated
            ),
            ZipTestEntry(
                path: "shiroko-role/agents/openai.yaml",
                data: Data(openAIYaml.utf8),
                compression: .stored
            ),
            ZipTestEntry(
                path: "shiroko-role/references/research.md",
                data: Data(referenceMarkdown.utf8),
                compression: .stored
            ),
        ])

        let saved = try await viewModel.importFile(data: archive, sourceFileName: "shiroko-role.zip")

        #expect(saved.name == "Shiroko Role")
        #expect(saved.personality?.contains("Quiet tactical role skill.") == true)
        #expect(saved.systemPrompt == "Use the attached role skill as the authoritative behavior guide.")
        #expect(saved.decodedTags == ["perspective", "skill", "zip"])
        #expect(viewModel.cards.map(\.id) == [saved.id])

        let bundle = try #require(try await manager.fetchCharacterSkillBundle(characterCardId: saved.id))
        #expect(bundle.sourceKind == "zip")
        #expect(bundle.sourceFileName == "shiroko-role.zip")
        #expect(bundle.sourceArchiveSha256 == SHA256Hex.hash(data: archive))
        #expect(bundle.skillMarkdownRelativePath == "SKILL.md")
        #expect(bundle.skillMarkdownSha256 == SHA256Hex.hash(text: skillMarkdown))
        #expect(bundle.skillName == "shiroko-perspective")
        #expect(bundle.skillDescription.contains("Quiet tactical role skill."))
        #expect(bundle.skillShortDescription == "Quiet tactical role skill")
        let manifest = try JSONDecoder().decode(
            [CharacterSkillBundleFileManifestEntry].self,
            from: Data(bundle.fileManifestJSON.utf8)
        )
        #expect(manifest.map(\.relativePath).contains("references/research.md"))

        let materializer = CharacterSkillBundleMaterializer(databaseManager: manager, store: store)
        let material = try #require(try await materializer.materialize(characterCardId: saved.id))
        #expect(material.name == "shiroko-perspective")
        #expect(material.skillMarkdown == skillMarkdown)

        let referenceSearch = SkillReferenceSearchTool(databaseManager: manager, store: store)
        let searchResult = try await referenceSearch.call(
            SkillReferenceSearchToolInput(
                characterCardId: saved.id,
                query: "cycling equipment",
                limit: 1
            )
        )
        let entry = try #require(searchResult.entries.first)
        #expect(entry.relativePath == "references/research.md")
        #expect(entry.excerpt.contains("Cycling equipment"))
    }
}

private enum ZipTestCompression {
    case stored
    case deflated

    var method: UInt16 {
        switch self {
        case .stored:
            0
        case .deflated:
            8
        }
    }
}

private struct ZipTestEntry {
    var path: String
    var data: Data
    var compression: ZipTestCompression
}

private func makeZipArchive(entries: [ZipTestEntry]) throws -> Data {
    struct CentralEntry {
        var pathData: Data
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    var archive = Data()
    var centralEntries: [CentralEntry] = []

    for entry in entries {
        let pathData = Data(entry.path.utf8)
        let payload: Data
        switch entry.compression {
        case .stored:
            payload = entry.data
        case .deflated:
            payload = try rawDeflate(entry.data)
        }

        let localHeaderOffset = archive.count
        archive.appendUInt32LE(0x0403_4B50)
        archive.appendUInt16LE(20)
        archive.appendUInt16LE(0x0800)
        archive.appendUInt16LE(entry.compression.method)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt32LE(UInt32(payload.count))
        archive.appendUInt32LE(UInt32(entry.data.count))
        archive.appendUInt16LE(UInt16(pathData.count))
        archive.appendUInt16LE(0)
        archive.append(pathData)
        archive.append(payload)

        centralEntries.append(
            CentralEntry(
                pathData: pathData,
                compressionMethod: entry.compression.method,
                compressedSize: payload.count,
                uncompressedSize: entry.data.count,
                localHeaderOffset: localHeaderOffset
            )
        )
    }

    let centralDirectoryOffset = archive.count
    for entry in centralEntries {
        archive.appendUInt32LE(0x0201_4B50)
        archive.appendUInt16LE(20)
        archive.appendUInt16LE(20)
        archive.appendUInt16LE(0x0800)
        archive.appendUInt16LE(entry.compressionMethod)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt32LE(UInt32(entry.compressedSize))
        archive.appendUInt32LE(UInt32(entry.uncompressedSize))
        archive.appendUInt16LE(UInt16(entry.pathData.count))
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt32LE(0)
        archive.appendUInt32LE(UInt32(entry.localHeaderOffset))
        archive.append(entry.pathData)
    }

    let centralDirectorySize = archive.count - centralDirectoryOffset
    archive.appendUInt32LE(0x0605_4B50)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(0)
    archive.appendUInt16LE(UInt16(centralEntries.count))
    archive.appendUInt16LE(UInt16(centralEntries.count))
    archive.appendUInt32LE(UInt32(centralDirectorySize))
    archive.appendUInt32LE(UInt32(centralDirectoryOffset))
    archive.appendUInt16LE(0)
    return archive
}

private func rawDeflate(_ data: Data) throws -> Data {
    var stream = z_stream()
    let initStatus = deflateInit2_(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        -15,
        8,
        Z_DEFAULT_STRATEGY,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
        throw NSError(domain: "zlib", code: Int(initStatus))
    }
    defer { deflateEnd(&stream) }

    var output = Data(count: max(64, data.count * 2 + 64))
    let status: Int32 = data.withUnsafeBytes { inputBuffer in
        output.withUnsafeMutableBytes { outputBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(inputBuffer.count)
            stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(outputBuffer.count)
            return deflate(&stream, Z_FINISH)
        }
    }
    guard status == Z_STREAM_END else {
        throw NSError(domain: "zlib", code: Int(status))
    }
    output.count = Int(stream.total_out)
    return output
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }
}
