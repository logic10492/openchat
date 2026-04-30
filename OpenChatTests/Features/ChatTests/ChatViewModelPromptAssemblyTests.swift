import Foundation
import Testing

@testable import OpenChat

private final class RequestCapture: @unchecked Sendable {
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

private struct ChatFailingEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "TestEmbedding",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced failure"]
            )
        )
    }
}

private struct ChatEmptyVectorStore: MemoryVectorStore {
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {}
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {}

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)] {
        []
    }

    func delete(entryId: String) async throws {}
    func deleteAll(characterCardId: String) async throws {}
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

@MainActor
@Suite("Chat prompt assembly")
struct ChatViewModelPromptAssemblyTests {
    @Test func test_current_parameters_preserve_reasoning_effort() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation()
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: database,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: database, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: database,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: database),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        viewModel.thinkingEnabled = true
        viewModel.thinkingBudget = 8192
        viewModel.reasoningEffort = ReasoningEffort.max

        let parameters = viewModel.currentParameters

        #expect(parameters.isThinkingEnabled == true)
        #expect(parameters.reasoningEffort == .max)
    }

    @Test func test_saveConversationSettings_persistsCompressionMode() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(
            id: "conversation-compression-mode",
            contextStrategy: .compression,
            compressionMode: .standard
        )
        try await database.saveConversation(conversation)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: database,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: database, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: database,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: database),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        viewModel.selectedCompressionMode = .highIntelligence
        await viewModel.saveConversationSettings()

        let saved = try await database.fetchConversation(id: conversation.id)
        #expect(saved?.compressionModeValue == .highIntelligence)
    }

    @Test func test_selected_provider_dialect_falls_back_to_default_model_when_saved_model_is_stale() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-deepseek",
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-deepseek",
            endpointId: endpoint.id,
            modelId: "deepseek-v4-pro",
            maxContextTokens: 1_000_000,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.deepSeekV4.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        var conversation = TestHelpers.makeConversation()
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = "removed-model"

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)

        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: database,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: database, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: database,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: database),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        await viewModel.loadModelsForEndpoint()

        #expect(viewModel.selectedProviderDialect == .deepSeekV4)
    }

    @Test func test_selected_provider_dialect_without_default_uses_earliest_created_model() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let endpoint = APIEndpointRecord(
            id: "endpoint-mixed",
            name: "Mixed",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: older,
            updatedAt: newer
        )
        let runtimeFallbackModel = EndpointModelRecord(
            id: "model-older",
            endpointId: endpoint.id,
            modelId: "z-local-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: false,
            isManual: true,
            createdAt: older
        )
        let sortedFirstModel = EndpointModelRecord(
            id: "model-newer",
            endpointId: endpoint.id,
            modelId: "a-deepseek-v4-pro",
            maxContextTokens: 1_000_000,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.deepSeekV4.rawValue,
            isDefault: false,
            isManual: true,
            createdAt: newer
        )
        var conversation = TestHelpers.makeConversation()
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = "removed-model"

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(runtimeFallbackModel)
        try await database.saveEndpointModel(sortedFirstModel)

        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: database,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: database, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: database,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: database),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        await viewModel.loadModelsForEndpoint()

        #expect(viewModel.selectedProviderDialect == .openAICompatible)
    }

    @Test func test_sendMessage_sends_current_input_once() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-1",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-1",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "assistant",
                content: "Previous assistant turn.",
                sortOrder: 1
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(APIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let contextManager = ContextManager(databaseManager: databaseManager, apiClient: apiClient)
        let memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: EmbeddingService(),
            vectorStore: VectorStore(databaseManager: databaseManager),
            apiClient: apiClient
        )
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: contextManager,
            memoryManager: memoryManager,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "What is this?"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.load())
        let currentInputMessages = request.messages.filter {
            $0.role == "user" && $0.content.contains("What is this?")
        }
        #expect(currentInputMessages.count == 1)
        let currentTurn = try #require(currentInputMessages.first)
        #expect(currentTurn.content.contains("[Time] "))

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let storedCurrentInputs = storedMessages.filter {
            $0.role == "user" && $0.content == "What is this?"
        }
        #expect(storedCurrentInputs.count == 1)
    }

    @Test func test_sendMessage_includes_recent_memory_when_semantic_retrieval_fails() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-memory-fallback",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-memory-fallback",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "card-memory-fallback")
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try card.insert(db)
        }
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-silver-key",
                characterCardId: card.id,
                content: "Ava promised to remember the silver key.",
                memoryType: .fact,
                importance: 90
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(APIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: apiClient),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: ChatFailingEmbeddingProvider(),
                vectorStore: ChatEmptyVectorStore(),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "What did you promise?"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.load())
        #expect(request.messages.contains {
            $0.role == "system" && $0.content.contains("Ava promised to remember the silver key.")
        })
    }

    @Test func test_sendMessage_orders_four_layer_prompt_in_api_request() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-four-layer",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-four-layer",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "card-four-layer")
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try card.insert(db)
        }
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "assistant",
                content: "Previous assistant turn.",
                sortOrder: 1
            )
        )
        try await databaseManager.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-four-layer",
                characterCardId: card.id,
                content: "Ava remembers the brass lantern.",
                memoryType: .fact,
                importance: 90
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(APIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: apiClient),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: ChatFailingEmbeddingProvider(),
                vectorStore: ChatEmptyVectorStore(),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "CURRENT_INPUT_UNIQUE_TEXT"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.load())
        let messages = request.messages
        let historyIndex = try #require(messages.firstIndex { $0.content.contains("Previous assistant turn") || $0.content.contains("[Previously]") })
        let exampleIndex = try #require(messages.firstIndex { $0.content.contains("[Example Dialogs]") })
        let memoryIndex = try #require(messages.firstIndex { $0.content.contains("[Memories]") })
        let currentTurnIndex = try #require(messages.firstIndex { $0.content.contains("CURRENT_INPUT_UNIQUE_TEXT") })

        #expect(historyIndex < exampleIndex)
        #expect(exampleIndex < memoryIndex)
        #expect(memoryIndex < currentTurnIndex)
        #expect(currentTurnIndex == messages.indices.last)
        #expect(messages[currentTurnIndex].role == "user")
        #expect(messages[currentTurnIndex].content.contains("[Time] "))
        #expect(messages.filter { $0.role == "user" && $0.content.contains("CURRENT_INPUT_UNIQUE_TEXT") }.count == 1)
    }

    @Test func test_editMessage_deletesAffectedCompressionCheckpoints() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "edit-checkpoint", contextStrategy: .compression)
        let user = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "old user", sortOrder: 1)
        let assistant = TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "old assistant", sortOrder: 2)
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            sourceHash: CompressionSourceHasher.hash(messages: [user, assistant]),
            summary: "old summary"
        )
        try await databaseManager.write { db in
            try conversation.insert(db)
            try user.insert(db)
            try assistant.insert(db)
            try checkpoint.insert(db)
        }

        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        await viewModel.editMessage(user.id, newContent: "edited user")

        let checkpoints = try await databaseManager.fetchCompressionCheckpoints(conversationId: conversation.id)
        #expect(checkpoints.isEmpty)
    }

    @Test func test_deleteMessage_deletesAffectedCompressionCheckpoints() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "delete-checkpoint", contextStrategy: .compression)
        let user = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "old user", sortOrder: 1)
        let assistant = TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "old assistant", sortOrder: 2)
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            sourceHash: CompressionSourceHasher.hash(messages: [user, assistant]),
            summary: "old summary"
        )
        try await databaseManager.write { db in
            try conversation.insert(db)
            try user.insert(db)
            try assistant.insert(db)
            try checkpoint.insert(db)
        }

        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: APIClient(),
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: APIClient()),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: APIClient()
            ),
            titleGenerator: TitleGenerator(apiClient: APIClient()),
            appState: AppState()
        )

        await viewModel.deleteMessage(user.id)

        let checkpoints = try await databaseManager.fetchCompressionCheckpoints(conversationId: conversation.id)
        #expect(checkpoints.isEmpty)
    }
}
