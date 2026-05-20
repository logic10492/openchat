import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("LibMan draft runtime")
struct LibrarianDraftTaskTests {
    @Test func test_librarianDraftExecutorReturnsCitedDraftWithoutDatabaseWrite() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "libman-card")
        let worldBook = TestHelpers.makeWorldBook(id: "libman-world")
        try await database.write { db in
            try card.insert(db)
            try worldBook.insert(db)
        }

        let capture = LibrarianRequestCapture()
        let draftJSON = """
        {
          "characterPatch": {
            "name": "Archivist Mara",
            "personality": "Careful and precise",
            "appearance": null,
            "physique": null,
            "speechStyle": "Measured",
            "backstory": null,
            "scenario": null,
            "exampleDialogs": [],
            "tags": ["archive"],
            "creatorNotes": "Draft only"
          },
          "worldBookEntries": [
            {
              "title": "Silver Archive",
              "keywords": ["archive", "silver"],
              "content": "The Silver Archive preserves sealed city records.",
              "priority": 70,
              "citations": [{"title": "Archive Note", "url": "https://example.com/archive", "excerpt": "sealed city records"}]
            }
          ],
          "citations": [{"title": "Archive Note", "url": "https://example.com/archive", "excerpt": "sealed city records"}],
          "warnings": []
        }
        """
        let escapedDraft = draftJSON
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: "\\n")
        let responseBody = #"{"id":"libman-response","choices":[{"index":0,"message":{"role":"assistant","content":"\#(escapedDraft)"},"finish_reason":"stop"}],"usage":{"prompt_tokens":11,"completion_tokens":13,"total_tokens":24}}"#
        let session = MockURLProtocol.makeSession { request in
            capture.store(try JSONDecoder().decode(APIRequest.self, from: try request.librarianTestBodyData()))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseBody.utf8))
        }
        let executor = LibrarianDraftExecutor(apiClient: APIClient(session: session))

        let result = try await executor.draft(
            request: LibrarianDraftRequest(
                target: .worldBook,
                userGoal: "Create a cited lore note.",
                sourceMaterials: [
                    LibrarianSourceMaterial(
                        title: "Archive Note",
                        url: "https://example.com/archive",
                        excerpt: "sealed city records"
                    ),
                ]
            ),
            endpoint: TestHelpers.makeEndpoint(modelName: "libman-model"),
            requestId: "libman-test",
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(result.output.characterPatch?.name == "Archivist Mara")
        #expect(result.output.worldBookEntries.first?.title == "Silver Archive")
        #expect(result.output.citations.first?.url == "https://example.com/archive")
        #expect(result.diagnostics.agent.kind == AgentKind.librarian)
        #expect(result.diagnostics.policy.visibilityPolicy.exposeDraftToUser)
        #expect(!result.diagnostics.policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(try await database.fetchCharacterCards().map(\.id) == [card.id])
        #expect(try await database.fetchWorldBookEntries(worldBookId: worldBook.id).isEmpty)

        let apiRequest = try #require(capture.load())
        #expect(apiRequest.model == "libman-model")
        #expect(apiRequest.stream == false)
        #expect(apiRequest.messages[0].role == "system")
        #expect(apiRequest.messages[0].content.contains("Create a user-visible draft only"))
        #expect(apiRequest.messages[1].role == "user")
        #expect(apiRequest.messages[1].content.contains("Create a cited lore note."))
    }

    @Test func test_librarianDraftParserRejectsDraftWithoutCitations() {
        let parser = LibrarianDraftParser()

        #expect(throws: LibrarianDraftError.missingCitations) {
            _ = try parser.parse(
                """
                {"characterPatch":{"name":"Mara","personality":null,"appearance":null,"physique":null,"speechStyle":null,"backstory":null,"scenario":null,"exampleDialogs":[],"tags":[],"creatorNotes":null},"worldBookEntries":[],"citations":[],"warnings":[]}
                """
            )
        }
    }
}

private extension URLRequest {
    func librarianTestBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw URLError(.cannotDecodeRawData)
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { pointer in
                httpBodyStream.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            if bytesRead < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if bytesRead == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }
        return data
    }
}

private final class LibrarianRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: APIRequest?

    func store(_ request: APIRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func load() -> APIRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}
