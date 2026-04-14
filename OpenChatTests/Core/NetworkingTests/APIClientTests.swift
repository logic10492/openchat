import Foundation
import Testing

@testable import OpenChat

@Suite("API client")
struct APIClientTests {
    @Test func test_sendMessage_builds_request_and_decodes_response() async throws {
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let endpoint = TestHelpers.makeEndpoint()
        let client = APIClient(session: session)

        let response = try await client.sendMessage(
            messages: [.init(role: "user", content: "Hello")],
            endpoint: endpoint,
            parameters: ModelParameters()
        )

        #expect(response.choices.first?.message.content == "hi")
    }

    @Test func test_streamMessage_yields_deltas_from_sse() async throws {
        let payload = """
        data: {"id":"1","choices":[{"index":0,"delta":{"content":"Hel"}}]}

        data: {"id":"1","choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":"stop"}]}

        data: [DONE]
        """
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint()
        let client = APIClient(session: session)

        var deltas: [StreamDelta] = []
        for try await delta in client.streamMessage(
            messages: [.init(role: "user", content: "Hello")],
            endpoint: endpoint,
            parameters: ModelParameters()
        ) {
            deltas.append(delta)
        }

        #expect(deltas.map(\.content) == ["Hel", "lo"])
        #expect(deltas.last?.finishReason == "stop")
    }
}
