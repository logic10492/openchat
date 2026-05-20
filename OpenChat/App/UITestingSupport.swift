import Foundation
import GRDB

enum UITestingSupport {
    static let launchArgument = "--ui-testing"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    @MainActor
    static func makeContainer() throws -> (DependencyContainer, AppState) {
        UITestingURLProtocol.register()
        let databaseManager = try DatabaseManager.inMemory()
        seed(databaseManager)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UITestingURLProtocol.self]
        let apiClient = APIClient(session: URLSession(configuration: configuration))
        let container = DependencyContainer(
            databaseManager: databaseManager,
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let appState = AppState()
        appState.selectedConversationID = Seed.conversationId
        return (container, appState)
    }

    private static func seed(_ databaseManager: DatabaseManager) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let endpoint = APIEndpointRecord(
            id: Seed.endpointId,
            name: "UI Mock Endpoint",
            baseURL: "https://ui-test.openchat.local/v1",
            apiKey: "ui-test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: Seed.modelRecordId,
            endpointId: endpoint.id,
            modelId: Seed.modelId,
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        let mara = CharacterCardRecord(
            id: Seed.maraCardId,
            name: "Mara",
            avatar: nil,
            personality: "Careful and direct",
            appearance: "Dark cloak",
            physique: "Lean",
            speechStyle: "Short replies",
            backstory: "Keeps watch over the old gate.",
            systemPrompt: nil,
            scenario: "A quiet stage used for UI tests.",
            exampleDialogs: nil,
            creatorNotes: nil,
            tags: #"["ui-test"]"#,
            worldBookId: nil,
            createdAt: now,
            updatedAt: now
        )
        let io = CharacterCardRecord(
            id: Seed.ioCardId,
            name: "Io",
            avatar: nil,
            personality: "Observant and precise",
            appearance: "Silver coat",
            physique: "Compact",
            speechStyle: "Measured replies",
            backstory: "Records stage events.",
            systemPrompt: nil,
            scenario: "A quiet stage used for UI tests.",
            exampleDialogs: nil,
            creatorNotes: nil,
            tags: #"["ui-test"]"#,
            worldBookId: nil,
            createdAt: now,
            updatedAt: now
        )
        let conversation = ConversationRecord(
            id: Seed.conversationId,
            title: "UI Stage Test",
            characterCardId: Seed.maraCardId,
            apiEndpointId: Seed.endpointId,
            modelName: Seed.modelId,
            contextStrategy: ContextStrategy.truncation.rawValue,
            compressionMode: CompressionMode.standard.rawValue,
            customScenario: nil,
            modelParameters: nil,
            slowPlotMode: false,
            isTitleGenerated: true,
            isPinned: false,
            lastExtractedSortOrder: nil,
            createdAt: now,
            updatedAt: now
        )

        do {
            try databaseManager.dbQueue.write { db in
                try endpoint.insert(db)
                try model.insert(db)
                try mara.insert(db)
                try io.insert(db)
                try conversation.insert(db)
            }
        } catch {
            assertionFailure("Failed to seed UI testing database: \(error.localizedDescription)")
        }
    }

    enum Seed {
        static let endpointId = "ui-test-endpoint"
        static let modelRecordId = "ui-test-model-record"
        static let modelId = "ui-test-model"
        static let conversationId = "ui-test-conversation"
        static let maraCardId = "ui-test-card-mara"
        static let ioCardId = "ui-test-card-io"
    }
}

final class UITestingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "OpenChatUITestingURLProtocolHandled"

    static func register() {
        URLProtocol.registerClass(Self.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }
        return request.url?.host == "ui-test.openchat.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private var requestBody: Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }

    private var requestJSON: [String: Any]? {
        guard let body = requestBody else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private var isStreamingRequest: Bool {
        guard let stream = requestJSON?["stream"] as? Bool else { return true }
        return stream
    }

    private var contentType: String {
        isStreamingRequest ? "text/event-stream" : "application/json"
    }

    private var payload: String {
        if isStreamingRequest {
            return """
            data: {"id":"ui-test","choices":[{"index":0,"delta":{"content":"UI stage reply"},"finish_reason":"stop"}]}

            data: [DONE]

            """
        }
        let participantId = directorParticipantId ?? ""
        return """
        {
          "id": "ui-test-director",
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "content": "{\\"speakerPlan\\":[{\\"participantId\\":\\"\(participantId)\\",\\"intent\\":\\"respondToUser\\"}],\\"stageInstructions\\":[]}"
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 8,
            "completion_tokens": 6,
            "total_tokens": 14
          }
        }
        """
    }

    private var directorParticipantId: String? {
        guard let messages = requestJSON?["messages"] as? [[String: Any]],
              let user = messages.last(where: { $0["role"] as? String == "user" }),
              let content = user["content"] as? String,
              let contentData = content.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let participants = payload["participants"] as? [[String: Any]]
        else {
            return nil
        }
        return participants.first(where: { $0["displayName"] as? String == "Mara" })?["id"] as? String
            ?? participants.first?["id"] as? String
    }
}
