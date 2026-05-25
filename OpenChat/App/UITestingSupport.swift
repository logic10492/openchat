import Foundation
import GRDB

enum UITestingSupport {
    static let launchArgument = "--ui-testing"
    static let edgeEffectsLaunchArgument = "--ui-testing-chat-edge-effects"
    static let contextMenuLaunchArgument = "--ui-testing-chat-context-menu"
    static let prefillLaunchArgument = "--ui-testing-chat-prefill"
    static let vibeWaitingDelayLaunchArgument = "--ui-testing-vibe-waiting-delay"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private static var usesEdgeEffectFixture: Bool {
        ProcessInfo.processInfo.arguments.contains(edgeEffectsLaunchArgument)
    }

    private static var usesContextMenuFixture: Bool {
        ProcessInfo.processInfo.arguments.contains(contextMenuLaunchArgument)
    }

    private static var usesPrefillFixture: Bool {
        ProcessInfo.processInfo.arguments.contains(prefillLaunchArgument)
    }

    static var usesVibeWaitingDelay: Bool {
        ProcessInfo.processInfo.arguments.contains(vibeWaitingDelayLaunchArgument)
    }

    @MainActor
    static func makeContainer() throws -> (DependencyContainer, AppState) {
        UITestingURLProtocol.register()
        let databaseManager = try DatabaseManager.inMemory()
        seed(
            databaseManager,
            includeEdgeEffectMessages: usesEdgeEffectFixture,
            includeContextMenuMessages: usesContextMenuFixture
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UITestingURLProtocol.self]
        let apiClient = APIClient(session: URLSession(configuration: configuration))
        let container = DependencyContainer(
            databaseManager: databaseManager,
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let appState = AppState()
        appState.selectedConversationID = usesPrefillFixture ? Seed.prefillConversationId : Seed.conversationId
        return (container, appState)
    }

    private static func seed(
        _ databaseManager: DatabaseManager,
        includeEdgeEffectMessages: Bool,
        includeContextMenuMessages: Bool
    ) {
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
        let prefillConversation = ConversationRecord(
            id: Seed.prefillConversationId,
            title: "UI Prefill Test",
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
        let stage = StageRecord(
            id: Seed.stageId,
            conversationId: conversation.id,
            title: "UI Stage",
            directorMode: DirectorMode.agent.rawValue,
            isEnabled: true,
            createdAt: now,
            updatedAt: now
        )
        let maraParticipant = StageParticipantRecord(
            id: Seed.maraParticipantId,
            stageId: stage.id,
            characterCardId: mara.id,
            displayName: "Mara",
            visibility: StageParticipantVisibility.present.rawValue,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now
        )
        let ioParticipant = StageParticipantRecord(
            id: Seed.ioParticipantId,
            stageId: stage.id,
            characterCardId: io.id,
            displayName: "Io",
            visibility: StageParticipantVisibility.present.rawValue,
            isActive: true,
            sortOrder: 1,
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
                try prefillConversation.insert(db)
                try stage.insert(db)
                try maraParticipant.insert(db)
                try ioParticipant.insert(db)
                if usesPrefillFixture {
                    let prefillSeed = MessageRecord(
                        id: Seed.prefillSeedUserMessageId,
                        conversationId: prefillConversation.id,
                        role: "user",
                        content: "Prefill fixture opener",
                        tokenCount: 3,
                        isCompressed: false,
                        originalContent: nil,
                        sortOrder: 0,
                        createdAt: now.addingTimeInterval(-300),
                        reasoningContent: nil
                    )
                    try prefillSeed.insert(db)
                }
                if includeEdgeEffectMessages {
                    for message in edgeEffectMessages(conversationId: conversation.id, baseDate: now.addingTimeInterval(-7200)) {
                        try message.insert(db)
                    }
                } else if includeContextMenuMessages {
                    for message in contextMenuMessages(conversationId: conversation.id, baseDate: now.addingTimeInterval(-600)) {
                        try message.insert(db)
                    }
                }
            }
        } catch {
            assertionFailure("Failed to seed UI testing database: \(error.localizedDescription)")
        }
    }

    private static func edgeEffectMessages(conversationId: String, baseDate: Date) -> [MessageRecord] {
        (0..<28).map { index in
            let isUser = index.isMultiple(of: 3)
            let role = isUser ? "user" : "assistant"
            let speakerName = isUser ? nil : (index.isMultiple(of: 2) ? "Mara" : "Io")
            var record = MessageRecord(
                id: "ui-edge-message-\(index)",
                conversationId: conversationId,
                role: role,
                content: edgeEffectMessageContent(index: index, isUser: isUser, speakerName: speakerName),
                tokenCount: 18,
                isCompressed: false,
                originalContent: nil,
                sortOrder: index,
                createdAt: baseDate.addingTimeInterval(Double(index * 73)),
                reasoningContent: nil
            )
            if let speakerName {
                record.stageId = Seed.stageId
                record.speakerKind = MessageSpeakerKind.participant.rawValue
                record.speakerId = speakerName == "Mara" ? Seed.maraParticipantId : Seed.ioParticipantId
                record.speakerName = speakerName
            }
            return record
        }
    }

    private static func edgeEffectMessageContent(index: Int, isUser: Bool, speakerName: String?) -> String {
        if isUser {
            return "Edge fixture turn \(index): keep the lantern low and describe what changes near the gate."
        }
        let speaker = speakerName ?? "Guide"
        return "\(speaker) edge fixture reply \(index). The glass at the edge should soften this text without turning into a flat cover. The sentence is intentionally long enough to cross the top and bottom bands during scroll verification."
    }

    private static func contextMenuMessages(conversationId: String, baseDate: Date) -> [MessageRecord] {
        [
            MessageRecord(
                id: Seed.contextMenuUserMessageId,
                conversationId: conversationId,
                role: "user",
                content: "Context menu bubble background fixture",
                tokenCount: 6,
                isCompressed: false,
                originalContent: nil,
                sortOrder: 0,
                createdAt: baseDate,
                reasoningContent: nil
            ),
            MessageRecord(
                id: Seed.contextMenuAssistantMessageId,
                conversationId: conversationId,
                role: "assistant",
                content: "Context menu assistant reply fixture.",
                tokenCount: 5,
                isCompressed: false,
                originalContent: nil,
                sortOrder: 1,
                createdAt: baseDate.addingTimeInterval(45),
                reasoningContent: nil
            ),
        ]
    }

    enum Seed {
        static let endpointId = "ui-test-endpoint"
        static let modelRecordId = "ui-test-model-record"
        static let modelId = "ui-test-model"
        static let conversationId = "ui-test-conversation"
        static let prefillConversationId = "ui-test-prefill-conversation"
        static let maraCardId = "ui-test-card-mara"
        static let ioCardId = "ui-test-card-io"
        static let stageId = "ui-test-stage"
        static let maraParticipantId = "ui-test-participant-mara"
        static let ioParticipantId = "ui-test-participant-io"
        static let contextMenuUserMessageId = "ui-context-menu-user"
        static let contextMenuAssistantMessageId = "ui-context-menu-assistant"
        static let prefillSeedUserMessageId = "ui-prefill-seed-user"
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
        if UITestingSupport.usesVibeWaitingDelay {
            Thread.sleep(forTimeInterval: 3.5)
        }

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
            let content = streamingContent
            return """
            data: {"id":"ui-test","choices":[{"index":0,"delta":{"content":"\(content)"},"finish_reason":"stop"}]}

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

    private var streamingContent: String {
        guard let messages = requestJSON?["messages"] as? [[String: Any]] else {
            return "UI stage reply"
        }
        let joined = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        if joined.contains("Active Speaker: Io") {
            return "Io UI stage reply"
        }
        if joined.contains("Active Speaker: Mara") {
            return "Mara UI stage reply"
        }
        return "UI stage reply"
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
