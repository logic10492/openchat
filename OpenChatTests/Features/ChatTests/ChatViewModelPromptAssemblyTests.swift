import Foundation
import Testing

@testable import OpenChat

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: APIRequest?
    private var responsesRequest: ResponsesAPIRequest?

    func store(_ request: APIRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func store(_ request: ResponsesAPIRequest) {
        lock.lock()
        defer { lock.unlock() }
        responsesRequest = request
    }

    func load() -> APIRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func loadResponsesRequest() -> ResponsesAPIRequest? {
        lock.lock()
        defer { lock.unlock() }
        return responsesRequest
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
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

private struct ChatFixedEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 0.9 : 0.8
        return embedding
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

private func restore(_ defaults: UserDefaults, key: String, value: Any?) {
    if let value {
        defaults.set(value, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
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

        viewModel.usesCustomModelParameters = true
        viewModel.thinkingEnabled = true
        viewModel.thinkingBudget = 8192
        viewModel.reasoningEffort = ReasoningEffort.max

        let parameters = viewModel.currentParameters

        #expect(parameters.isThinkingEnabled == true)
        #expect(parameters.reasoningEffort == .max)
    }

    @Test func test_current_parameters_inherit_global_defaults_without_conversation_override() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation()
        let defaults = UserDefaults.standard
        let oldTemperature = defaults.object(forKey: "default_temperature")
        let oldTopP = defaults.object(forKey: "default_top_p")
        let oldMaxTokens = defaults.object(forKey: "default_max_tokens")
        defer {
            restore(defaults, key: "default_temperature", value: oldTemperature)
            restore(defaults, key: "default_top_p", value: oldTopP)
            restore(defaults, key: "default_max_tokens", value: oldMaxTokens)
        }
        defaults.set(0.35, forKey: "default_temperature")
        defaults.set(0.72, forKey: "default_top_p")
        defaults.set(4096, forKey: "default_max_tokens")

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

        #expect(viewModel.usesCustomModelParameters == false)
        #expect(viewModel.currentParameters.temperature == 0.35)
        #expect(viewModel.currentParameters.topP == 0.72)
        #expect(viewModel.currentParameters.maxTokens == 4096)
    }

    @Test func test_legacy_default_conversation_parameters_inherit_global_defaults() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        var conversation = TestHelpers.makeConversation()
        conversation.modelParameters = RecordCoders.encode(
            ModelParameters(
                temperature: ModelParameters.openChatDefaultTemperature,
                topP: ModelParameters.openChatDefaultTopP,
                maxTokens: 1024
            )
        )

        let defaults = UserDefaults.standard
        let oldTemperature = defaults.object(forKey: "default_temperature")
        let oldTopP = defaults.object(forKey: "default_top_p")
        let oldMaxTokens = defaults.object(forKey: "default_max_tokens")
        defer {
            restore(defaults, key: "default_temperature", value: oldTemperature)
            restore(defaults, key: "default_top_p", value: oldTopP)
            restore(defaults, key: "default_max_tokens", value: oldMaxTokens)
        }
        defaults.set(0.31, forKey: "default_temperature")
        defaults.set(0.61, forKey: "default_top_p")
        defaults.set(3072, forKey: "default_max_tokens")

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

        #expect(viewModel.usesCustomModelParameters == false)
        #expect(viewModel.currentParameters.temperature == 0.31)
        #expect(viewModel.currentParameters.topP == 0.61)
        #expect(viewModel.currentParameters.maxTokens == 3072)
    }

    @Test func test_saveConversationSettings_preserves_global_model_inheritance() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conversation-model-inheritance")
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

        viewModel.modelTemperature = 1.25
        viewModel.modelTopP = 0.4
        viewModel.modelMaxTokens = 2048
        viewModel.usesCustomModelParameters = false
        await viewModel.saveConversationSettings()

        let saved = try await database.fetchConversation(id: conversation.id)
        #expect(saved?.modelParameters == nil)
    }

    @Test func test_enable_custom_model_parameters_prefills_global_defaults() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation()
        let defaults = UserDefaults.standard
        let oldTemperature = defaults.object(forKey: "default_temperature")
        let oldTopP = defaults.object(forKey: "default_top_p")
        let oldMaxTokens = defaults.object(forKey: "default_max_tokens")
        defer {
            restore(defaults, key: "default_temperature", value: oldTemperature)
            restore(defaults, key: "default_top_p", value: oldTopP)
            restore(defaults, key: "default_max_tokens", value: oldMaxTokens)
        }
        defaults.set(0.42, forKey: "default_temperature")
        defaults.set(0.68, forKey: "default_top_p")
        defaults.set(6144, forKey: "default_max_tokens")

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

        viewModel.modelTemperature = 1.25
        viewModel.modelTopP = 0.4
        viewModel.modelMaxTokens = 2048
        viewModel.setUsesCustomModelParameters(true)

        #expect(viewModel.usesCustomModelParameters == true)
        #expect(viewModel.modelTemperature == 0.42)
        #expect(viewModel.modelTopP == 0.68)
        #expect(viewModel.modelMaxTokens == 6144)
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

    @Test func test_saveConversationSettings_stageEnabledDoesNotOverwriteConversationCharacter() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let originalCard = TestHelpers.makeCharacterCard(id: "original-card", name: "Mara")
        let candidateCard = TestHelpers.makeCharacterCard(id: "candidate-card", name: "Io")
        let conversation: ConversationRecord = {
            var record = TestHelpers.makeConversation(id: "stage-character-save-boundary")
            record.characterCardId = originalCard.id
            return record
        }()
        try await database.write { db in
            try originalCard.insert(db)
            try candidateCard.insert(db)
            try conversation.insert(db)
        }
        _ = try await database.createStage(
            conversationId: conversation.id,
            title: "Stage Boundary",
            directorMode: .silent
        )
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

        await viewModel.loadStage()
        viewModel.selectedCharacterCardID = candidateCard.id
        await viewModel.saveConversationSettings()

        let saved = try await database.fetchConversation(id: conversation.id)
        #expect(saved?.characterCardId == originalCard.id)
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

    @Test func test_prefillMode_afterUserInputAlternatesAssistantAndUserWithoutNetworkRequest() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "prefill-card", name: "Mara")
        var conversation = TestHelpers.makeConversation(id: "prefill-conversation", slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.isTitleGenerated = true
        try await databaseManager.saveCharacterCard(card)
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "user",
                content: "I step into the room.",
                sortOrder: 1
            )
        )

        let requestCounter = RequestCounter()
        let session = MockURLProtocol.makeSession { _ in
            requestCounter.increment()
            throw URLError(.badServerResponse)
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: apiClient),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        await viewModel.loadMessages()
        viewModel.isPrefillModeEnabled = true
        viewModel.inputText = "Mara answers before the model is called."
        await viewModel.sendMessage()
        viewModel.inputText = "I answer the hand-authored reply."
        await viewModel.sendMessage()
        viewModel.inputText = "Mara continues the hand-authored exchange."
        await viewModel.sendMessage()

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        #expect(storedMessages.map(\.role) == ["user", "assistant", "user", "assistant"])
        #expect(storedMessages.map(\.content) == [
            "I step into the room.",
            "Mara answers before the model is called.",
            "I answer the hand-authored reply.",
            "Mara continues the hand-authored exchange.",
        ])
        #expect(storedMessages.map(\.speakerName) == [nil, "Mara", nil, "Mara"])
        #expect(storedMessages.map(\.tokenCount) == [
            TokenCounter.count("I step into the room."),
            TokenCounter.count("Mara answers before the model is called."),
            TokenCounter.count("I answer the hand-authored reply."),
            TokenCounter.count("Mara continues the hand-authored exchange."),
        ])
        #expect(viewModel.messages.map(\.role) == ["user", "assistant", "user", "assistant"])
        #expect(viewModel.prefillNextRole == .userMessage)
        #expect(viewModel.inputText.isEmpty)
        #expect(viewModel.isPrefillModeEnabled)
        #expect(viewModel.streamTask == nil)
        #expect(viewModel.isGenerating == false)
        #expect(requestCounter.load() == 0)
    }

    @Test func test_prefillMode_withoutPriorUserInputStartsWithUserMessage() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "prefill-empty-card", name: "Mara")
        var conversation = TestHelpers.makeConversation(id: "prefill-empty-conversation", slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.isTitleGenerated = true
        try await databaseManager.saveCharacterCard(card)
        try await databaseManager.saveConversation(conversation)

        let requestCounter = RequestCounter()
        let session = MockURLProtocol.makeSession { _ in
            requestCounter.increment()
            throw URLError(.badServerResponse)
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: apiClient),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        await viewModel.loadMessages()
        #expect(viewModel.prefillNextRole == .userMessage)
        viewModel.isPrefillModeEnabled = true
        viewModel.inputText = "I start by writing the user side."
        await viewModel.sendMessage()
        viewModel.inputText = "Mara follows with the character side."
        await viewModel.sendMessage()

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        #expect(storedMessages.map(\.role) == ["user", "assistant"])
        #expect(storedMessages.map(\.content) == [
            "I start by writing the user side.",
            "Mara follows with the character side.",
        ])
        #expect(storedMessages.map(\.speakerName) == [nil, "Mara"])
        #expect(viewModel.prefillNextRole == .userMessage)
        #expect(viewModel.isPrefillModeEnabled)
        #expect(requestCounter.load() == 0)
    }

    @Test func test_prefilledExchange_isIncludedInNextGenerationHistory() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "prefill-endpoint",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "prefill-model-record",
            endpointId: endpoint.id,
            modelId: "prefill-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "prefill-history-card", name: "Mara")
        var conversation = TestHelpers.makeConversation(id: "prefill-history-conversation", slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true
        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.saveCharacterCard(card)
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "user",
                content: "I provide the last ordinary user input.",
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
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Generated after prefill"},"finish_reason":"stop"}]}

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
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        await viewModel.loadMessages()
        viewModel.isPrefillModeEnabled = true
        viewModel.inputText = "Mara writes the hand-authored opening reply."
        await viewModel.sendMessage()
        viewModel.inputText = "I answer while prefill remains enabled."
        await viewModel.sendMessage()
        viewModel.inputText = "Mara keeps speaking in the hand-authored exchange."
        await viewModel.sendMessage()
        viewModel.isPrefillModeEnabled = false
        viewModel.inputText = "Continue from that opening."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let request = try #require(capture.load())
        let handAuthoredHistory = request.messages.filter {
            $0.content == "Mara writes the hand-authored opening reply."
                || $0.content == "I answer while prefill remains enabled."
                || $0.content == "Mara keeps speaking in the hand-authored exchange."
        }
        #expect(handAuthoredHistory.map(\.role) == ["assistant", "user", "assistant"])
        #expect(handAuthoredHistory.map(\.content) == [
            "Mara writes the hand-authored opening reply.",
            "I answer while prefill remains enabled.",
            "Mara keeps speaking in the hand-authored exchange.",
        ])
        let currentInputs = request.messages.filter {
            $0.role == "user" && $0.content.contains("Continue from that opening.")
        }
        #expect(currentInputs.count == 1)

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        #expect(storedMessages.map(\.role) == ["user", "assistant", "user", "assistant", "user", "assistant"])
        #expect(storedMessages.map(\.content) == [
            "I provide the last ordinary user input.",
            "Mara writes the hand-authored opening reply.",
            "I answer while prefill remains enabled.",
            "Mara keeps speaking in the hand-authored exchange.",
            "Continue from that opening.",
            "Generated after prefill",
        ])
    }

    @Test func test_directorInput_isPersistedAsStageInstructionNotUserMessage() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "director-input-conversation")
        try await databaseManager.saveConversation(conversation)
        _ = try await databaseManager.createStage(
            conversationId: conversation.id,
            title: "Stage",
            directorMode: .userControlled
        )
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

        await viewModel.loadStage()
        viewModel.stageInputRole = .director
        viewModel.inputText = "Let Mara enter late."
        await viewModel.sendMessage()

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let context = try #require(try await databaseManager.fetchStageContext(conversationId: conversation.id))

        #expect(storedMessages.isEmpty)
        #expect(context.instructions.map(\.content) == ["Let Mara enter late."])
        #expect(viewModel.inputText.isEmpty)
    }

    @Test func test_stageParticipantPrompt_persistsSpeakerMetadata() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-stage",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-stage",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let mara = TestHelpers.makeCharacterCard(id: "card-mara", name: "Mara")
        let io = TestHelpers.makeCharacterCard(id: "card-io", name: "Io")
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = mara.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try mara.insert(db)
            try io.insert(db)
        }
        try await databaseManager.saveConversation(conversation)
        let stage = try await databaseManager.createStage(
            conversationId: conversation.id,
            title: "Stage",
            directorMode: .silent
        )
        _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: mara)
        _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: io)
        try await databaseManager.saveStageInstruction(
            StageInstructionRecord(
                id: "stage-instruction-1",
                stageId: stage.id,
                source: StageInstructionSource.user.rawValue,
                content: "Keep the scene quiet.",
                visibility: StageInstructionVisibility.hiddenFromCharacters.rawValue,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )

        let capture = RequestSequenceCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            let apiRequest = try JSONDecoder().decode(APIRequest.self, from: body)
            let index = capture.store(apiRequest)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let content = index == 0 ? "Mara stage reply" : "Io stage reply"
            let payload = """
            data: {"id":"\(index)","choices":[{"index":0,"delta":{"content":"\(content)"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let backgroundSpeakers = RequestStringCapture()
        let apiClient = APIClient(session: session)
        let backgroundManager = BackgroundManager { request, _ in
            let context = try #require(request.stageContext)
            #expect(context.stageId == stage.id)
            #expect(context.activeParticipants.map(\.characterCardId) == [mara.id, io.id])
            backgroundSpeakers.store(context.activeSpeaker?.displayName ?? "")
            #expect(context.directorInstructions.map(\.content) == ["Keep the scene quiet."])
            return BackgroundPacket(
                entries: [],
                omitted: [],
                diagnostics: BackgroundDiagnostics(
                    requestId: request.conversation.id,
                    startedAt: now,
                    endedAt: now,
                    elapsedMilliseconds: 0,
                    policyProfile: [:],
                    agentPolicySummary: [:],
                    sourceSummaries: [],
                    inputCandidateCount: 0,
                    selectedIds: [],
                    omitted: [],
                    fallbacks: [],
                    warnings: []
                )
            )
        }
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
            backgroundManager: backgroundManager,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "Mara, answer first."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let requests = capture.load()
        #expect(requests.count == 2)
        #expect(backgroundSpeakers.load() == ["Mara", "Io"])
        #expect(requests[0].messages.contains {
            $0.role == "system" && $0.content.contains("[Stage]")
        })
        #expect(requests[0].messages.contains {
            $0.role == "system" && $0.content.contains("[Director Instructions]") && $0.content.contains("Keep the scene quiet.")
        })
        #expect(requests[0].messages.contains {
            $0.role == "system" && $0.content.contains("[Stage Participants]") && $0.content.contains("Active Speaker: Mara")
        })
        #expect(requests[1].messages.contains {
            $0.role == "system" && $0.content.contains("[Stage Participants]") && $0.content.contains("Active Speaker: Io")
        })

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let assistants = storedMessages.filter { $0.role == "assistant" }
        #expect(assistants.map(\.content) == ["Mara stage reply", "Io stage reply"])
        #expect(assistants.allSatisfy { $0.stageId == stage.id })
        #expect(assistants.allSatisfy { $0.speakerKindValue == .participant })
        #expect(assistants.map(\.speakerName) == ["Mara", "Io"])
    }

    @Test func test_sendMessage_responsesMode_foldsStageBlocksIntoInstructionsInOrder() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-stage-responses",
            name: "Local Responses",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-stage-responses",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.responses.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let mara = TestHelpers.makeCharacterCard(id: "card-stage-responses-mara", name: "Mara")
        let io = TestHelpers.makeCharacterCard(id: "card-stage-responses-io", name: "Io")
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = mara.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try mara.insert(db)
            try io.insert(db)
        }
        try await databaseManager.saveConversation(conversation)
        let stage = try await databaseManager.createStage(
            conversationId: conversation.id,
            title: "Responses Stage",
            directorMode: .userControlled
        )
        _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: mara)
        _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: io)
        try await databaseManager.saveStageInstruction(
            StageInstructionRecord(
                id: "stage-responses-instruction-1",
                stageId: stage.id,
                source: StageInstructionSource.user.rawValue,
                content: "Keep the scene quiet.",
                visibility: StageInstructionVisibility.hiddenFromCharacters.rawValue,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(ResponsesAPIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            event: response.output_text.delta
            data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Done"}

            event: response.completed
            data: {"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":10,"output_tokens":1,"total_tokens":11}}}

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

        viewModel.inputText = "Mara, answer first."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.loadResponsesRequest())
        let instructions = try #require(request.instructions)
        let stageRange = try #require(instructions.range(of: "[Stage]"))
        let participantsRange = try #require(instructions.range(of: "[Stage Participants]"))
        let directorRange = try #require(instructions.range(of: "[Director Instructions]"))

        #expect(stageRange.lowerBound < participantsRange.lowerBound)
        #expect(participantsRange.lowerBound < directorRange.lowerBound)
        #expect(instructions.contains("Director Mode: userControlled"))
        #expect(instructions.contains("Active Speaker: Io"))
        #expect(instructions.contains("Keep the scene quiet."))
        #expect(!request.input.contains { $0.content.contains("[Stage]") })
        #expect(!request.input.contains { $0.content.contains("[Director Instructions]") })
        #expect(request.input.filter { $0.role == "user" && $0.content.contains("Mara, answer first.") }.count == 1)
    }

    @Test func test_stream_failure_after_partial_delta_persists_visible_assistant_content() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-partial-failure",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-partial-failure",
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

        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Partial reply"},"finish_reason":null}]}

            data: {"invalid":
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let contextManager = ContextManager(databaseManager: databaseManager, apiClient: apiClient)
        let memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: ChatFailingEmbeddingProvider(),
            vectorStore: ChatEmptyVectorStore(),
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

        viewModel.inputText = "Continue."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let assistant = storedMessages.first { $0.role == "assistant" }
        #expect(assistant?.content == "Partial reply")
        #expect(viewModel.messages.contains { $0.role == "assistant" && $0.content == "Partial reply" })
        #expect(viewModel.isGenerating == false)
        #expect(viewModel.streamTask == nil)
    }

    @Test func test_sendMessage_includes_high_value_memory_when_semantic_retrieval_fails() async throws {
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
                id: "memory-recent-noise",
                characterCardId: card.id,
                content: "Ava recently counted clouds.",
                memoryType: .event,
                importance: 10
            )
        )
        try await databaseManager.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "memory-silver-key",
                characterCardId: card.id,
                content: "Ava promised to remember the silver key.",
                memoryType: .relationship,
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
        #expect(!request.messages.contains {
            $0.role == "system" && $0.content.contains("Ava recently counted clouds.")
        })
    }

    @Test func test_sendMessage_triggers_memory_extraction_from_persisted_sortOrder_boundary() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-persisted-extraction",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-persisted-extraction",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "card-persisted-extraction")
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
        for index in 1...3 {
            try await databaseManager.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: index.isMultiple(of: 2) ? "assistant" : "user",
                    content: "Persisted old turn \(index)",
                    sortOrder: index
                )
            )
        }

        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            let requestObject = try JSONDecoder().decode(APIRequest.self, from: body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: requestObject.stream ? ["Content-Type": "text/event-stream"] : ["Content-Type": "application/json"]
            )!

            if requestObject.stream {
                let payload = """
                data: {"id":"1","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}]}

                data: [DONE]
                """
                return (response, Data(payload.utf8))
            }

            let responseBody = """
            {"id":"memory-extraction","choices":[{"index":0,"message":{"role":"assistant","content":"[{\\"content\\":\\"Ava remembers the persisted boundary.\\",\\"type\\":\\"fact\\",\\"importance\\":80}]"},"finish_reason":"stop"}],"usage":null}
            """
            return (response, Data(responseBody.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: ContextManager(databaseManager: databaseManager, apiClient: apiClient),
            memoryManager: MemoryManager(
                databaseManager: databaseManager,
                embeddingService: ChatFixedEmbeddingProvider(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "New turn reaches extraction threshold."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let savedConversation = try await databaseManager.fetchConversation(id: conversation.id)
        #expect(savedConversation?.lastExtractedSortOrder == 4)
        let memories = try await databaseManager.fetchMemories(characterCardId: card.id)
        #expect(memories.map(\.content).contains("Ava remembers the persisted boundary."))
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

    @Test func test_semantic_world_book_entry_reaches_world_book_entries_block() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-world-book-semantic",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-world-book-semantic",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-book-semantic")
        let baseCard = TestHelpers.makeCharacterCard(id: "card-world-book-semantic")
        let card = CharacterCardRecord(
            id: baseCard.id,
            name: baseCard.name,
            avatar: baseCard.avatar,
            personality: baseCard.personality,
            appearance: baseCard.appearance,
            physique: baseCard.physique,
            speechStyle: baseCard.speechStyle,
            backstory: baseCard.backstory,
            systemPrompt: baseCard.systemPrompt,
            scenario: baseCard.scenario,
            exampleDialogs: baseCard.exampleDialogs,
            creatorNotes: baseCard.creatorNotes,
            tags: baseCard.tags,
            worldBookId: worldBook.id,
            createdAt: baseCard.createdAt,
            updatedAt: baseCard.updatedAt
        )
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true
        let semanticEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "semantic-only-world-book-entry",
            title: "Moon Archive",
            keywords: ["selenite-vault"],
            content: "The moon archive stores silent maps."
        )

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try worldBook.insert(db)
            try card.insert(db)
            try semanticEntry.insert(db)
        }
        try await databaseManager.saveConversation(conversation)

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
        let worldBookVectorStore = WorldBookVectorStore(databaseManager: databaseManager)
        let worldBookEmbeddingIndexer = WorldBookEmbeddingIndexer(
            databaseManager: databaseManager,
            embeddingProvider: ChatFixedEmbeddingProvider(),
            vectorStore: worldBookVectorStore
        )
        let worldBookSource = WorldBookSource(
            embeddingProvider: ChatFixedEmbeddingProvider(),
            vectorStore: worldBookVectorStore
        )
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
            worldBookEmbeddingIndexer: worldBookEmbeddingIndexer,
            worldBookSource: worldBookSource,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "Where are the old maps kept?"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let request = try #require(capture.load())
        let worldBookBlock = try #require(request.messages.first {
            $0.role == "system" && $0.content.contains("[World Book Entries]")
        })
        #expect(worldBookBlock.content.contains("[World Book: Moon Archive]"))
        #expect(worldBookBlock.content.contains("The moon archive stores silent maps."))
    }

    @Test func test_world_book_source_semantic_failure_falls_back_to_keyword_block() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-world-book-keyword-fallback",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-world-book-keyword-fallback",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-book-keyword-fallback")
        let baseCard = TestHelpers.makeCharacterCard(id: "card-world-book-keyword-fallback")
        let card = CharacterCardRecord(
            id: baseCard.id,
            name: baseCard.name,
            avatar: baseCard.avatar,
            personality: baseCard.personality,
            appearance: baseCard.appearance,
            physique: baseCard.physique,
            speechStyle: baseCard.speechStyle,
            backstory: baseCard.backstory,
            systemPrompt: baseCard.systemPrompt,
            scenario: baseCard.scenario,
            exampleDialogs: baseCard.exampleDialogs,
            creatorNotes: baseCard.creatorNotes,
            tags: baseCard.tags,
            worldBookId: worldBook.id,
            createdAt: baseCard.createdAt,
            updatedAt: baseCard.updatedAt
        )
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true
        let keywordEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "keyword-fallback-world-book-entry",
            title: "Dragon Treaty",
            keywords: ["dragon"],
            content: "Dragon treaties are stored in the west hall."
        )

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.write { db in
            try worldBook.insert(db)
            try card.insert(db)
            try keywordEntry.insert(db)
        }
        try await databaseManager.saveConversation(conversation)

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
        let worldBookSource = WorldBookSource(
            embeddingProvider: ChatFailingEmbeddingProvider(),
            vectorStore: WorldBookVectorStore(databaseManager: databaseManager)
        )
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
            worldBookSource: worldBookSource,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "Tell me about the dragon agreement."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let request = try #require(capture.load())
        let worldBookBlock = try #require(request.messages.first {
            $0.role == "system" && $0.content.contains("[World Book Entries]")
        })
        #expect(worldBookBlock.content.contains("[World Book: Dragon Treaty]"))
        #expect(worldBookBlock.content.contains("Dragon treaties are stored in the west hall."))
        #expect(request.messages.filter { $0.content.contains("[World Book Entries]") }.count == 1)
    }

    @Test func test_sendMessage_uses_background_packet_for_prompt_blocks() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-background-packet",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-background-packet",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "card-background-packet")
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
                characterCardId: card.id,
                content: "Direct memory should not be injected."
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
        let backgroundManager = BackgroundManager { request, _ in
            BackgroundPacket(
                entries: [
                    BackgroundEntry(
                        id: "memory:packet",
                        sourceType: .memory,
                        sourceId: "packet",
                        title: "event",
                        content: "Packet-selected memory.",
                        rank: 1,
                        score: 1,
                        estimatedTokens: 4,
                        reason: "test",
                        metadata: ["memoryType": "event", "requestInput": request.currentInput]
                    ),
                ],
                omitted: [],
                diagnostics: BackgroundDiagnostics(
                    requestId: request.conversation.id,
                    startedAt: now,
                    endedAt: now,
                    elapsedMilliseconds: 0,
                    policyProfile: [:],
                    agentPolicySummary: [:],
                    sourceSummaries: [],
                    inputCandidateCount: 1,
                    selectedIds: ["memory:packet"],
                    omitted: [],
                    fallbacks: [],
                    warnings: []
                )
            )
        }
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
            backgroundManager: backgroundManager,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "Use background packet."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let request = try #require(capture.load())
        let memoryBlock = try #require(request.messages.first {
            $0.role == "system" && $0.content.contains("[Memories]")
        })
        #expect(memoryBlock.content.contains("Packet-selected memory."))
        #expect(!memoryBlock.content.contains("Direct memory should not be injected."))
        #expect(request.messages.filter { $0.role == "user" && $0.content.contains("Use background packet.") }.count == 1)
    }

    @Test func test_sendMessage_responses_mode_folds_memories_into_instructions_without_user_duplication() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-responses-memory-shape",
            name: "Local Responses",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-responses-memory-shape",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.responses.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let card = TestHelpers.makeCharacterCard(id: "card-responses-memory-shape")
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
                id: "memory-responses-memory-shape",
                characterCardId: card.id,
                content: "Ava remembers the brass lantern.",
                memoryType: .fact,
                importance: 90
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(ResponsesAPIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            event: response.output_text.delta
            data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Done"}

            event: response.completed
            data: {"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":10,"output_tokens":1,"total_tokens":11}}}

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

        viewModel.inputText = "CURRENT_RESPONSES_INPUT_UNIQUE_TEXT"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.loadResponsesRequest())
        let instructions = try #require(request.instructions)
        let stableRange = try #require(instructions.range(of: "You are"))
        let memoryRange = try #require(instructions.range(of: "[Memories]"))

        #expect(stableRange.lowerBound < memoryRange.lowerBound)
        #expect(instructions.contains("Ava remembers the brass lantern."))
        #expect(!request.input.contains { $0.content.contains("[Memories]") })
        #expect(request.input.filter { $0.role == "user" && $0.content.contains("CURRENT_RESPONSES_INPUT_UNIQUE_TEXT") }.count == 1)
        #expect(request.input.last?.role == "user")
        #expect(request.input.last?.content.contains("[Time] ") == true)
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

    @Test func test_editUserMessage_truncatesTailAndRegeneratesFromEditedPrefix() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-edit-tail",
            name: "Edit Tail Endpoint",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-edit-tail",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        var conversation = TestHelpers.makeConversation(id: "edit-tail", slowPlotMode: false)
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true
        let conversationRecord = conversation
        let userA = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "a", sortOrder: 1)
        let assistantA = TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "response a", sortOrder: 2)
        let userB = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "b", sortOrder: 3)
        let assistantB = TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "response b", sortOrder: 4)
        let userC = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "c", sortOrder: 5)
        let assistantC = TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "response c", sortOrder: 6)
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 4,
            sourceHash: CompressionSourceHasher.hash(messages: [userA, assistantA, userB, assistantB]),
            summary: "old branch summary"
        )
        try await databaseManager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
            try conversationRecord.insert(db)
            try userA.insert(db)
            try assistantA.insert(db)
            try userB.insert(db)
            try assistantB.insert(db)
            try userC.insert(db)
            try assistantC.insert(db)
            try checkpoint.insert(db)
        }

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
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"new response"},"finish_reason":"stop"}]}

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
                embeddingService: EmbeddingService(),
                vectorStore: VectorStore(databaseManager: databaseManager),
                apiClient: apiClient
            ),
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        await viewModel.loadMessages()
        await viewModel.editMessage(userA.id, newContent: "edited a")

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        #expect(storedMessages.map(\.role) == ["user", "assistant"])
        #expect(storedMessages.map(\.content) == ["edited a", "new response"])
        #expect(storedMessages.map(\.sortOrder) == [1, 2])
        #expect(viewModel.messages.map(\.content) == ["edited a", "new response"])

        let request = try #require(capture.load())
        #expect(request.messages.filter { $0.role == "user" && $0.content.contains("edited a") }.count == 1)
        #expect(!request.messages.contains { $0.role == "assistant" && $0.content == "response a" })
        #expect(!request.messages.contains { $0.role == "user" && $0.content == "b" })
        #expect(!request.messages.contains { $0.role == "assistant" && $0.content == "response b" })
        #expect(!request.messages.contains { $0.role == "user" && $0.content == "c" })
        #expect(!request.messages.contains { $0.role == "assistant" && $0.content == "response c" })

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

    @Test func test_stageSpeakerBlocksSplitIntoMultipleAssistantMessages() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        var conversation = TestHelpers.makeConversation(id: "stage-speaker-split")
        conversation.isTitleGenerated = true
        let endpoint = APIEndpointRecord(
            id: "endpoint-stage-split",
            name: "Stage Split Endpoint",
            baseURL: "https://stage-split.test/v1",
            apiKey: "key",
            isDefault: true,
            createdAt: .now,
            updatedAt: .now
        )
        let model = EndpointModelRecord(
            id: "model-stage-split",
            endpointId: endpoint.id,
            modelId: "stage-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: .now
        )
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        let conversationRecord = conversation
        let mara = TestHelpers.makeCharacterCard(id: "card-mara", name: "Mara")
        let io = TestHelpers.makeCharacterCard(id: "card-io", name: "Io")
        try await databaseManager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
            try conversationRecord.insert(db)
            try mara.insert(db)
            try io.insert(db)
        }
        let stage = try await databaseManager.createStage(
            conversationId: conversationRecord.id,
            title: "Split Stage",
            directorMode: .silent
        )
        let maraParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: mara)
        let ioParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: io)

        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"[Speaker: Mara]\\nThe gate is sealed.\\n[/Speaker]\\n[Speaker: Io]\\nThen we wait.\\n[/Speaker]"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversationRecord,
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

        viewModel.inputText = "Both respond."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let assistantRecords = try await databaseManager.fetchMessages(conversationId: conversationRecord.id)
            .filter { $0.role == "assistant" }
        #expect(assistantRecords.count == 2)
        #expect(assistantRecords.map(\.content) == ["The gate is sealed.", "Then we wait."])
        #expect(assistantRecords.map(\.speakerId) == [maraParticipant.id, ioParticipant.id])
        #expect(assistantRecords.map(\.speakerName) == ["Mara", "Io"])
        #expect(assistantRecords.allSatisfy { $0.stageId == stage.id })
        #expect(viewModel.messages.filter { $0.role == "assistant" }.map(\.content) == ["The gate is sealed.", "Then we wait."])
    }

    @Test func test_stageTwoParticipantsUseSeparateCharacterPrompts() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        var conversation = TestHelpers.makeConversation(id: "stage-two-character-calls")
        conversation.isTitleGenerated = true
        let endpoint = APIEndpointRecord(
            id: "endpoint-stage-two-calls",
            name: "Stage Two Calls Endpoint",
            baseURL: "https://stage-two-calls.test/v1",
            apiKey: "key",
            isDefault: true,
            createdAt: .now,
            updatedAt: .now
        )
        let model = EndpointModelRecord(
            id: "model-stage-two-calls",
            endpointId: endpoint.id,
            modelId: "stage-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: .now
        )
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        let conversationRecord = conversation
        let mara = TestHelpers.makeCharacterCard(
            id: "card-stage-two-mara",
            name: "Mara",
            systemPrompt: "You are Mara. Speak with moonlit restraint."
        )
        let io = TestHelpers.makeCharacterCard(
            id: "card-stage-two-io",
            name: "Io",
            systemPrompt: "You are Io. Speak with bright certainty."
        )
        try await databaseManager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
            try conversationRecord.insert(db)
            try mara.insert(db)
            try io.insert(db)
        }
        let stage = try await databaseManager.createStage(
            conversationId: conversationRecord.id,
            title: "Two Speaker Stage",
            directorMode: .silent
        )
        let maraParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: mara)
        let ioParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: io)

        let capture = RequestSequenceCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            let apiRequest = try JSONDecoder().decode(APIRequest.self, from: body)
            let index = capture.store(apiRequest)
            let content = index == 0 ? "Mara answers." : "Io answers."
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"\(index)","choices":[{"index":0,"delta":{"content":"\(content)"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversationRecord,
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

        viewModel.inputText = "Both respond."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let requests = capture.load()
        #expect(requests.count == 2)
        let firstMessages = requests[0].messages.map(\.content).joined(separator: "\n")
        let secondMessages = requests[1].messages.map(\.content).joined(separator: "\n")
        #expect(firstMessages.contains("You are Mara. Speak with moonlit restraint."))
        #expect(firstMessages.contains("Active Speaker: Mara"))
        #expect(!firstMessages.contains("You are Io. Speak with bright certainty."))
        #expect(secondMessages.contains("You are Io. Speak with bright certainty."))
        #expect(secondMessages.contains("Active Speaker: Io"))
        #expect(!secondMessages.contains("You are Mara. Speak with moonlit restraint."))
        #expect(secondMessages.contains("Mara: Mara answers."))
        let secondTurnMessages = requests[1].messages.filter { $0.role == "user" || $0.role == "assistant" }
        let userTurnIndex = try #require(secondTurnMessages.firstIndex {
            $0.role == "user" && $0.content.contains("Both respond.")
        })
        let maraTurnIndex = try #require(secondTurnMessages.firstIndex {
            $0.role == "user" && $0.content == "Mara: Mara answers."
        })
        #expect(userTurnIndex < maraTurnIndex)
        #expect(maraTurnIndex == secondTurnMessages.indices.last)

        let assistantRecords = try await databaseManager.fetchMessages(conversationId: conversationRecord.id)
            .filter { $0.role == "assistant" }
        #expect(assistantRecords.map(\.content) == ["Mara answers.", "Io answers."])
        #expect(assistantRecords.map(\.speakerId) == [maraParticipant.id, ioParticipant.id])
        #expect(assistantRecords.map(\.speakerName) == ["Mara", "Io"])
    }

    @Test func test_stageResponderOrderOverridesDefaultSpeakers() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        var conversation = TestHelpers.makeConversation(id: "stage-responder-order")
        conversation.isTitleGenerated = true
        let endpoint = APIEndpointRecord(
            id: "endpoint-stage-responder-order",
            name: "Stage Responder Endpoint",
            baseURL: "https://stage-responder-order.test/v1",
            apiKey: "key",
            isDefault: true,
            createdAt: .now,
            updatedAt: .now
        )
        let model = EndpointModelRecord(
            id: "model-stage-responder-order",
            endpointId: endpoint.id,
            modelId: "stage-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: .now
        )
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        let conversationRecord = conversation
        let mara = TestHelpers.makeCharacterCard(id: "card-order-mara", name: "Mara")
        let io = TestHelpers.makeCharacterCard(id: "card-order-io", name: "Io")
        let ren = TestHelpers.makeCharacterCard(id: "card-order-ren", name: "Ren")
        try await databaseManager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
            try conversationRecord.insert(db)
            try mara.insert(db)
            try io.insert(db)
            try ren.insert(db)
        }
        let stage = try await databaseManager.createStage(
            conversationId: conversationRecord.id,
            title: "Responder Order Stage",
            directorMode: .silent
        )
        _ = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: mara)
        let ioParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: io)
        let renParticipant = try await databaseManager.addStageParticipant(stageId: stage.id, characterCard: ren)

        let capture = RequestSequenceCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            let apiRequest = try JSONDecoder().decode(APIRequest.self, from: body)
            let index = capture.store(apiRequest)
            let content = index == 0 ? "Ren answers." : "Io answers."
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"\(index)","choices":[{"index":0,"delta":{"content":"\(content)"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let viewModel = ChatViewModel(
            conversation: conversationRecord,
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

        await viewModel.loadStage()
        viewModel.markStageResponderSelectionCustomized()
        viewModel.stageResponderIds = [renParticipant.id, ioParticipant.id]
        viewModel.inputText = "Respond in the directed order."
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let requests = capture.load()
        #expect(requests.count == 2)
        let firstMessages = requests[0].messages.map(\.content).joined(separator: "\n")
        let secondMessages = requests[1].messages.map(\.content).joined(separator: "\n")
        #expect(firstMessages.contains("Active Speaker: Ren"))
        #expect(secondMessages.contains("Active Speaker: Io"))
        #expect(!firstMessages.contains("Active Speaker: Mara"))

        let assistantRecords = try await databaseManager.fetchMessages(conversationId: conversationRecord.id)
            .filter { $0.role == "assistant" }
        #expect(assistantRecords.map(\.content) == ["Ren answers.", "Io answers."])
        #expect(assistantRecords.map(\.speakerId) == [renParticipant.id, ioParticipant.id])
        #expect(assistantRecords.map(\.speakerName) == ["Ren", "Io"])
    }
}

private final class RequestSequenceCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [APIRequest] = []

    func store(_ request: APIRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let index = requests.count
        requests.append(request)
        return index
    }

    func load() -> [APIRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private final class RequestStringCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func store(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    func load() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
