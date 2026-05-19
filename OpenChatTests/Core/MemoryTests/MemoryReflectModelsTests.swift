import Foundation
import Testing

@testable import OpenChat

@Suite("Memory reflect contract")
struct MemoryReflectModelsTests {
    @Test func test_reflect_request_requires_source_memory_ids() throws {
        #expect(throws: MemoryReflectContractError.self) {
            _ = try MemoryReflectRequest(
                characterCardId: "card-1",
                task: .summarize,
                sourceMemoryIds: ["  "]
            )
        }
    }

    @Test func test_reflect_observation_requires_based_on_memory_ids() throws {
        #expect(throws: MemoryReflectContractError.self) {
            _ = try MemoryReflectObservation(
                content: "Ava links the lantern promise to the old map.",
                memoryType: .relationship,
                basedOnMemoryIds: [],
                suggestedAction: .insertObservation
            )
        }
    }

    @Test func test_reflect_observation_normalizes_content_and_confidence() throws {
        let observation = try MemoryReflectObservation(
            content: "  Ava connects the brass lantern to the rescue plan.  ",
            memoryType: .summary,
            basedOnMemoryIds: [" memory-a ", "memory-b"],
            confidence: 1.4,
            suggestedAction: .insertObservation
        )

        #expect(observation.content == "Ava connects the brass lantern to the rescue plan.")
        #expect(observation.basedOnMemoryIds == ["memory-a", "memory-b"])
        #expect(observation.confidence == 1.0)
        #expect(observation.suggestedAction == .insertObservation)
    }

    @Test func test_reflect_link_relations_are_minimal_supported_set() {
        let relations = Set(MemoryEntryLinkRelation.allCases.map(\.rawValue))

        #expect(relations == ["summarizes", "duplicates", "reinforces"])
    }

    @Test func test_reflect_tasks_and_actions_match_contract_values() {
        let tasks = Set(MemoryReflectTask.allCases.map(\.rawValue))
        let actions = Set(MemoryReflectAction.allCases.map(\.rawValue))

        #expect(tasks == ["summarize", "dedupe", "resolve_conflict", "relationship_observation"])
        #expect(actions == ["insert_observation", "mark_duplicate", "needs_user_review"])
    }

    @Test func test_reflect_parser_parses_valid_json_object() throws {
        let parser = MemoryReflectParser()

        let observation = try parser.parse(
            """
            {"content":"Ava links the lantern promise to the old map.","type":"summary","basedOn":["memory-a","memory-b"],"confidence":0.82,"suggestedAction":"insert_observation"}
            """,
            sourceMemoryIds: ["memory-a", "memory-b"]
        )

        #expect(observation.content == "Ava links the lantern promise to the old map.")
        #expect(observation.memoryType == .summary)
        #expect(observation.basedOnMemoryIds == ["memory-a", "memory-b"])
        #expect(observation.confidence == 0.82)
        #expect(observation.suggestedAction == .insertObservation)
    }

    @Test func test_reflect_parser_strips_markdown_json_fence() throws {
        let parser = MemoryReflectParser()

        let observation = try parser.parse(
            """
            ```json
            {"content":"Ava treats the lantern as a rescue signal.","type":"relationship","basedOn":["memory-a"],"confidence":0.6,"suggestedAction":"needs_user_review"}
            ```
            """,
            sourceMemoryIds: ["memory-a"]
        )

        #expect(observation.content == "Ava treats the lantern as a rescue signal.")
        #expect(observation.memoryType == .relationship)
        #expect(observation.basedOnMemoryIds == ["memory-a"])
        #expect(observation.suggestedAction == .needsUserReview)
    }

    @Test func test_reflect_parser_rejects_missing_based_on() {
        let parser = MemoryReflectParser()

        expectReflectError(.missingBasedOn) {
            _ = try parser.parse(
                """
                {"content":"Ava remembers the lantern.","type":"summary","confidence":0.8,"suggestedAction":"insert_observation"}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }
    }

    @Test func test_reflect_parser_rejects_unknown_based_on_source_id() {
        let parser = MemoryReflectParser()

        expectReflectError(.unknownBasedOnIds(["memory-z"])) {
            _ = try parser.parse(
                """
                {"content":"Ava remembers the lantern.","type":"summary","basedOn":["memory-a","memory-z"],"confidence":0.8,"suggestedAction":"insert_observation"}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }
    }

    @Test func test_reflect_parser_rejects_invalid_action_and_type() {
        let parser = MemoryReflectParser()

        expectReflectError(.invalidMemoryType("note")) {
            _ = try parser.parse(
                """
                {"content":"Ava remembers the lantern.","type":"note","basedOn":["memory-a"],"confidence":0.8,"suggestedAction":"insert_observation"}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }

        expectReflectError(.invalidSuggestedAction("silently_replace")) {
            _ = try parser.parse(
                """
                {"content":"Ava remembers the lantern.","type":"summary","basedOn":["memory-a"],"confidence":0.8,"suggestedAction":"silently_replace"}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }
    }

    @Test func test_reflect_parser_rejects_invalid_confidence() {
        let parser = MemoryReflectParser()

        expectReflectError(.invalidConfidence) {
            _ = try parser.parse(
                """
                {"content":"Ava remembers the lantern.","type":"summary","basedOn":["memory-a"],"confidence":true,"suggestedAction":"insert_observation"}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }
    }

    @Test func test_reflect_parser_rejects_array_or_multiple_observations() {
        let parser = MemoryReflectParser()

        expectReflectError(.multipleObservationsNotSupported) {
            _ = try parser.parse(
                """
                [
                  {"content":"One","type":"summary","basedOn":["memory-a"],"suggestedAction":"insert_observation"},
                  {"content":"Two","type":"summary","basedOn":["memory-a"],"suggestedAction":"insert_observation"}
                ]
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }

        expectReflectError(.multipleObservationsNotSupported) {
            _ = try parser.parse(
                """
                {"observations":[{"content":"One","type":"summary","basedOn":["memory-a"],"suggestedAction":"insert_observation"}]}
                """,
                sourceMemoryIds: ["memory-a"]
            )
        }
    }

    @Test func test_reflect_executor_rejects_missing_source_memory() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let executor = MemoryReflectExecutor(databaseManager: database, apiClient: APIClient())
        let request = try MemoryReflectRequest(
            characterCardId: "card-a",
            task: .summarize,
            sourceMemoryIds: ["missing-memory"]
        )

        await expectReflectError(.missingSourceMemories(["missing-memory"])) {
            _ = try await executor.reflect(request: request, endpoint: TestHelpers.makeEndpoint())
        }
    }

    @Test func test_reflect_executor_rejects_cross_character_source_memory() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let cardA = TestHelpers.makeCharacterCard(id: "card-a")
        let cardB = TestHelpers.makeCharacterCard(id: "card-b")
        try await database.write { db in
            try cardA.insert(db)
            try cardB.insert(db)
        }
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-b",
                characterCardId: cardB.id,
                content: "Ava remembers the lantern."
            )
        )

        let executor = MemoryReflectExecutor(databaseManager: database, apiClient: APIClient())
        let request = try MemoryReflectRequest(
            characterCardId: cardA.id,
            task: .summarize,
            sourceMemoryIds: ["memory-b"]
        )

        await expectReflectError(.crossCharacterMemory(id: "memory-b", expectedCharacterCardId: cardA.id, actualCharacterCardId: cardB.id)) {
            _ = try await executor.reflect(request: request, endpoint: TestHelpers.makeEndpoint())
        }
    }

    @Test func test_reflect_executor_sends_stable_request_and_returns_draft_without_db_write() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect")
        try await database.write { db in try card.insert(db) }
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-a",
                characterCardId: card.id,
                content: "Ava found the brass lantern.",
                memoryType: .event
            )
        )
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-b",
                characterCardId: card.id,
                content: "The lantern is a rescue signal.",
                memoryType: .fact
            )
        )

        let capture = MemoryReflectRequestCapture()
        let assistantContent = #"{"content":"Ava connects the brass lantern to rescue signaling.","type":"summary","basedOn":["memory-b","memory-a"],"confidence":0.75,"suggestedAction":"insert_observation"}"#
        let escapedContent = assistantContent
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        let responseBody = #"{"id":"reflect-response","choices":[{"index":0,"message":{"role":"assistant","content":"\#(escapedContent)"},"finish_reason":"stop"}],"usage":null}"#
        let session = MockURLProtocol.makeSession { request in
            capture.store(try JSONDecoder().decode(APIRequest.self, from: try request.openChatTestBodyData()))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseBody.utf8))
        }
        let executor = MemoryReflectExecutor(databaseManager: database, apiClient: APIClient(session: session))
        let request = try MemoryReflectRequest(
            characterCardId: card.id,
            task: .dedupe,
            sourceMemoryIds: ["memory-b", "memory-a"]
        )

        let result = try await executor.reflect(
            request: request,
            endpoint: TestHelpers.makeEndpoint(modelName: "reflect-model"),
            requestId: "reflect-request-1"
        )

        #expect(result.observation.content == "Ava connects the brass lantern to rescue signaling.")
        #expect(result.observation.basedOnMemoryIds == ["memory-b", "memory-a"])
        #expect(result.diagnostics.requestId == "reflect-request-1")
        #expect(result.diagnostics.task == .dedupe)
        #expect(result.diagnostics.sourceMemoryIds == ["memory-b", "memory-a"])
        #expect(result.diagnostics.modelId == "reflect-model")
        #expect(result.diagnostics.inputMessageCount == 2)
        #expect(result.diagnostics.parseRepairCount == 0)
        #expect(result.diagnostics.rejectedReason == nil)
        #expect(try await database.fetchMemoryCount(characterCardId: card.id) == 2)

        let apiRequest = try #require(capture.load())
        #expect(apiRequest.model == "reflect-model")
        #expect(apiRequest.stream == false)
        #expect(apiRequest.temperature == 0.2)
        #expect(apiRequest.topP == 0.9)
        #expect(apiRequest.maxTokens == 700)
        #expect(apiRequest.messages.count == 2)
        #expect(apiRequest.messages[0].role == "system")
        #expect(apiRequest.messages[0].content.contains("Return ONLY one JSON object"))
        #expect(apiRequest.messages[1].role == "user")

        let prompt = try #require(
            JSONSerialization.jsonObject(with: Data(apiRequest.messages[1].content.utf8)) as? [String: Any]
        )
        #expect(prompt["characterCardId"] as? String == card.id)
        #expect(prompt["task"] as? String == MemoryReflectTask.dedupe.rawValue)
        let sourceMemories = try #require(prompt["sourceMemories"] as? [[String: Any]])
        #expect(sourceMemories.count == 2)
        #expect(sourceMemories.compactMap { $0["id"] as? String } == ["memory-b", "memory-a"])
        #expect(sourceMemories.compactMap { $0["type"] as? String } == ["fact", "event"])
        #expect(Set(sourceMemories[0].keys) == ["id", "type", "content"])
        #expect(Set(sourceMemories[1].keys) == ["id", "type", "content"])
    }

    @Test func test_apply_reflect_observation_creates_entry_embedding_links_and_keeps_sources() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect-apply")
        let sourceA = TestHelpers.makeMemoryEntry(
            id: "apply-source-a",
            characterCardId: card.id,
            content: "Ava saved the brass lantern.",
            memoryType: .event,
            importance: 40
        )
        let sourceB = TestHelpers.makeMemoryEntry(
            id: "apply-source-b",
            characterCardId: card.id,
            content: "Ava uses lantern light for rescue signals.",
            memoryType: .fact,
            importance: 50
        )
        try await database.write { db in
            try card.insert(db)
            try sourceA.insert(db)
            try sourceB.insert(db)
        }
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let observation = try MemoryReflectObservation(
            content: "Ava connects the lantern to rescue signaling.",
            memoryType: .summary,
            basedOnMemoryIds: [sourceA.id, sourceB.id],
            confidence: 0.8,
            suggestedAction: .insertObservation
        )

        let applied = try await manager.applyReflectObservation(observation, characterCardId: card.id)

        let memories = try await database.fetchMemories(characterCardId: card.id)
        let links = try await database.fetchMemoryEntryLinks(fromMemoryEntryId: applied.id)
        #expect(applied.sourceConversationId == nil)
        #expect(applied.memoryTypeValue == .summary)
        #expect(applied.importance == 60)
        #expect(memories.map(\.id).contains(sourceA.id))
        #expect(memories.map(\.id).contains(sourceB.id))
        #expect(memories.map(\.id).contains(applied.id))
        #expect(try await vectorRowCount(entryId: applied.id, in: database) == 1)
        #expect(links.map(\.toMemoryEntryId) == [sourceA.id, sourceB.id])
        #expect(links.allSatisfy { $0.relationValue == .summarizes })
    }

    @Test func test_apply_reflect_observation_embedding_failure_rolls_back() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect-embedding-fail")
        let source = TestHelpers.makeMemoryEntry(id: "embedding-source", characterCardId: card.id)
        try await database.write { db in
            try card.insert(db)
            try source.insert(db)
        }
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFailingEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let observation = try MemoryReflectObservation(
            content: "Ava connects the source memory.",
            memoryType: .summary,
            basedOnMemoryIds: [source.id],
            suggestedAction: .insertObservation
        )

        do {
            _ = try await manager.applyReflectObservation(observation, characterCardId: card.id)
            Issue.record("Expected embedding failure to throw")
        } catch let error as MemoryError {
            guard case .embeddingFailed = error else {
                Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
        }

        #expect(try await database.fetchMemoryCount(characterCardId: card.id) == 1)
        #expect(try await database.fetchMemoryEntryLinks(memoryEntryIds: [source.id]) == [])
    }

    @Test func test_apply_reflect_observation_rejects_cross_character_or_missing_sources_before_write() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let cardA = TestHelpers.makeCharacterCard(id: "card-reflect-cross-a")
        let cardB = TestHelpers.makeCharacterCard(id: "card-reflect-cross-b")
        let otherSource = TestHelpers.makeMemoryEntry(id: "cross-source", characterCardId: cardB.id)
        try await database.write { db in
            try cardA.insert(db)
            try cardB.insert(db)
            try otherSource.insert(db)
        }
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let crossCharacter = try MemoryReflectObservation(
            content: "Ava should not link outside her card.",
            memoryType: .summary,
            basedOnMemoryIds: [otherSource.id],
            suggestedAction: .insertObservation
        )
        await expectReflectApplyThrows(MemoryReflectError.crossCharacterMemory(
            id: otherSource.id,
            expectedCharacterCardId: cardA.id,
            actualCharacterCardId: cardB.id
        )) {
            _ = try await manager.applyReflectObservation(crossCharacter, characterCardId: cardA.id)
        }

        let missing = try MemoryReflectObservation(
            content: "Ava should not link missing memories.",
            memoryType: .summary,
            basedOnMemoryIds: ["missing-source"],
            suggestedAction: .insertObservation
        )
        await expectReflectApplyThrows(MemoryReflectError.missingSourceMemories(["missing-source"])) {
            _ = try await manager.applyReflectObservation(missing, characterCardId: cardA.id)
        }

        #expect(try await database.fetchMemoryCount(characterCardId: cardA.id) == 0)
        #expect(try await database.fetchMemoryEntryLinks(memoryEntryIds: [otherSource.id]) == [])
    }

    @Test func test_apply_reflect_observation_rejects_non_insert_actions() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect-action-reject")
        let source = TestHelpers.makeMemoryEntry(id: "action-source", characterCardId: card.id)
        try await database.write { db in
            try card.insert(db)
            try source.insert(db)
        }
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        for action in [MemoryReflectAction.markDuplicate, .needsUserReview] {
            let observation = try MemoryReflectObservation(
                content: "Ava should review this manually.",
                memoryType: .summary,
                basedOnMemoryIds: [source.id],
                suggestedAction: action
            )
            await #expect(throws: MemoryReflectApplyError.unsupportedAction(action)) {
                _ = try await manager.applyReflectObservation(observation, characterCardId: card.id)
            }
        }

        #expect(try await database.fetchMemoryCount(characterCardId: card.id) == 1)
        #expect(try await database.fetchMemoryEntryLinks(memoryEntryIds: [source.id]) == [])
    }

    @MainActor
    @Test func test_memory_list_view_model_reflect_and_apply_success_reloads_list() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let keyStore = InMemoryAPIKeyStore()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect-viewmodel")
        let sourceA = TestHelpers.makeMemoryEntry(id: "vm-source-a", characterCardId: card.id)
        let sourceB = TestHelpers.makeMemoryEntry(id: "vm-source-b", characterCardId: card.id)
        try await saveDefaultEndpoint(in: database, keyStore: keyStore)
        try await database.write { db in
            try card.insert(db)
            try sourceA.insert(db)
            try sourceB.insert(db)
        }
        let apiClient = makeReflectAPIClient(
            content: "Ava summarizes both selected memories.",
            basedOnIds: [sourceA.id, sourceB.id]
        )
        let memoryManager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: keyStore
        )
        let viewModel = MemoryListViewModel(
            databaseManager: database,
            memoryManager: memoryManager,
            reflectExecutor: MemoryReflectExecutor(databaseManager: database, apiClient: apiClient),
            apiKeyStore: keyStore,
            characterCardId: card.id
        )

        await viewModel.loadMemories()
        viewModel.toggleMemorySelection(sourceA.id)
        viewModel.toggleMemorySelection(sourceB.id)
        await viewModel.runReflect(task: .summarize)

        #expect(viewModel.reflectState == .draft)
        #expect(viewModel.reflectDraft?.content == "Ava summarizes both selected memories.")
        #expect(viewModel.reflectErrorMessage == nil)

        await viewModel.applyReflectObservation()

        #expect(viewModel.reflectState == .idle)
        #expect(viewModel.reflectDraft == nil)
        #expect(viewModel.selectedMemoryIds.isEmpty)
        #expect(viewModel.memories.count == 3)
        #expect(viewModel.memories.contains { $0.content == "Ava summarizes both selected memories." })
    }

    @MainActor
    @Test func test_memory_list_view_model_apply_failure_keeps_draft_and_shows_error() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let keyStore = InMemoryAPIKeyStore()
        let card = TestHelpers.makeCharacterCard(id: "card-reflect-viewmodel-failure")
        let sourceA = TestHelpers.makeMemoryEntry(id: "vm-fail-source-a", characterCardId: card.id)
        let sourceB = TestHelpers.makeMemoryEntry(id: "vm-fail-source-b", characterCardId: card.id)
        try await saveDefaultEndpoint(in: database, keyStore: keyStore)
        try await database.write { db in
            try card.insert(db)
            try sourceA.insert(db)
            try sourceB.insert(db)
        }
        let apiClient = makeReflectAPIClient(
            content: "Ava summarizes both selected memories.",
            basedOnIds: [sourceA.id, sourceB.id]
        )
        let memoryManager = MemoryManager(
            databaseManager: database,
            embeddingService: MemoryReflectFailingEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: keyStore
        )
        let viewModel = MemoryListViewModel(
            databaseManager: database,
            memoryManager: memoryManager,
            reflectExecutor: MemoryReflectExecutor(databaseManager: database, apiClient: apiClient),
            apiKeyStore: keyStore,
            characterCardId: card.id
        )

        await viewModel.loadMemories()
        viewModel.toggleMemorySelection(sourceA.id)
        viewModel.toggleMemorySelection(sourceB.id)
        await viewModel.runReflect(task: .summarize)
        await viewModel.applyReflectObservation()

        #expect(viewModel.reflectState == .failed)
        #expect(viewModel.reflectDraft?.content == "Ava summarizes both selected memories.")
        #expect(viewModel.reflectErrorMessage?.isEmpty == false)
        #expect(viewModel.memories.count == 2)
    }

    private func expectReflectError(
        _ expected: MemoryReflectError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected \(expected), but no error was thrown.")
        } catch let error as MemoryReflectError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error).")
        }
    }

    private func expectReflectError(
        _ expected: MemoryReflectError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected), but no error was thrown.")
        } catch let error as MemoryReflectError {
            #expect(error == expected)
        } catch let error as MemoryReflectExecutorError {
            #expect(error.error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error).")
        }
    }

    private func expectReflectApplyThrows(
        _ expected: MemoryReflectError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected), but no error was thrown.")
        } catch let error as MemoryReflectError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error).")
        }
    }

    private func vectorRowCount(entryId: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM memory_embedding WHERE entry_id = ?",
                arguments: [entryId]
            ) ?? 0
        }
    }

    private func saveDefaultEndpoint(
        in database: DatabaseManager,
        keyStore: InMemoryAPIKeyStore
    ) async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let endpoint = APIEndpointRecord(
            id: "reflect-default-endpoint",
            name: "Reflect Default",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "reflect-default-model",
            endpointId: endpoint.id,
            modelId: "reflect-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try keyStore.saveKey("test-key", endpointId: endpoint.id)
    }

    private func makeReflectAPIClient(content: String, basedOnIds: [String]) -> APIClient {
        let basedOn = basedOnIds
            .map { #""\#($0)""# }
            .joined(separator: ",")
        let assistantContent = """
        {"content":"\(content)","type":"summary","basedOn":[\(basedOn)],"confidence":0.75,"suggestedAction":"insert_observation"}
        """
        let escapedContent = assistantContent
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        let responseBody = #"{"id":"reflect-response","choices":[{"index":0,"message":{"role":"assistant","content":"\#(escapedContent)"},"finish_reason":"stop"}],"usage":null}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseBody.utf8))
        }
        return APIClient(session: session)
    }
}

private final class MemoryReflectRequestCapture: @unchecked Sendable {
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

private struct MemoryReflectFixedEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 0.9 : 0.8
        return embedding
    }
}

private struct MemoryReflectFailingEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "MemoryReflectTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced embedding failure"]
            )
        )
    }
}

private extension URLRequest {
    func openChatTestBodyData() throws -> Data {
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
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}
