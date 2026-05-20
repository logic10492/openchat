import Foundation
import Testing

@testable import OpenChat

@Suite("LLM Director executor")
struct LLMDirectorExecutorTests {
    @Test func test_agentModeUsesLLMDirectorPlan() async throws {
        let context = makeStageContext(mode: .agent)
        let capture = DirectorRequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.directorTestBodyData()
            capture.store(String(decoding: body, as: UTF8.self))
            let requestObject = try JSONDecoder().decode(APIRequest.self, from: body)
            let userPayload = requestObject.messages.last?.content ?? ""
            let payloadData = try #require(userPayload.data(using: .utf8))
            let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            let participants = try #require(payload?["participants"] as? [[String: Any]])
            let ioId = try #require(participants.first(where: { $0["displayName"] as? String == "Io" })?["id"] as? String)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let responseBody = """
            {
              "id": "director-test",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "{\\"speakerPlan\\":[{\\"participantId\\":\\"\(ioId)\\",\\"intent\\":\\"advanceScene\\",\\"maxTokens\\":120}],\\"stageInstructions\\":[{\\"content\\":\\"Keep Mara quiet this turn.\\",\\"visibility\\":\\"hiddenFromCharacters\\"}],\\"warnings\\":[]}"
                  },
                  "finish_reason": "stop"
                }
              ],
              "usage": {"prompt_tokens": 10, "completion_tokens": 8, "total_tokens": 18}
            }
            """
            return (response, Data(responseBody.utf8))
        }

        let executor = LLMDirectorExecutor(
            apiClient: APIClient(session: session),
            endpoint: TestHelpers.makeEndpoint(),
            parameters: ModelParameters(maxTokens: 1_000)
        )

        let plan = try await executor.execute(
            DirectorRuntimeInput(
                stageContext: context,
                inputRole: .participant,
                currentInput: "Let Io answer."
            )
        )

        #expect(plan.participant?.displayName == "Io")
        #expect(plan.directorPlan.speakerPlan.first?.intent == .advanceScene)
        #expect(plan.directorPlan.speakerPlan.first?.maxTokens == 120)
        #expect(plan.visibleInstructions.map { $0.content }.contains("Keep Mara quiet this turn."))
        #expect(plan.directorPlan.diagnostics.metadata["runtime"] == "llm")
        #expect(capture.load()?.contains("\"stream\":false") == true)
    }

    @Test func test_invalidLLMOutputFallsBackToDeterministicPlan() async throws {
        let context = makeStageContext(mode: .agent)
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {
              "id": "director-test",
              "choices": [
                {
                  "index": 0,
                  "message": {"role": "assistant", "content": "not json"},
                  "finish_reason": "stop"
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }

        let executor = LLMDirectorExecutor(
            apiClient: APIClient(session: session),
            endpoint: TestHelpers.makeEndpoint(),
            parameters: ModelParameters(maxTokens: 1_000)
        )

        let plan = try await executor.execute(
            DirectorRuntimeInput(
                stageContext: context,
                inputRole: .participant,
                currentInput: "No explicit name."
            )
        )

        #expect(plan.participant?.displayName == "Mara")
        #expect(plan.directorPlan.diagnostics.metadata["runtime"] == "llm-fallback")
        #expect(plan.directorPlan.diagnostics.metadata["fallbackReason"] == "missing-json-object")
    }
}

private final class DirectorRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: String?

    func store(_ request: String) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private extension URLRequest {
    func directorTestBodyData() throws -> Data {
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

private func makeStageContext(mode: DirectorMode) -> StageContext {
    StageContext(
        stage: StageRecord(
            id: "stage-1",
            conversationId: "conversation-1",
            title: "Scene",
            directorMode: mode.rawValue,
            isEnabled: true,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ),
        participants: [
            StageParticipantRecord(
                id: "participant-mara",
                stageId: "stage-1",
                characterCardId: "card-mara",
                displayName: "Mara",
                visibility: StageParticipantVisibility.present.rawValue,
                isActive: true,
                sortOrder: 1,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            StageParticipantRecord(
                id: "participant-io",
                stageId: "stage-1",
                characterCardId: "card-io",
                displayName: "Io",
                visibility: StageParticipantVisibility.present.rawValue,
                isActive: true,
                sortOrder: 2,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
        ],
        instructions: []
    )
}
