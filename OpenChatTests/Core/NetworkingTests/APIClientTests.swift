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

    // MARK: - fetchModels

    @Test func test_fetchModels_decodes_response() async throws {
        let responseBody = #"{"object":"list","data":[{"id":"gpt-4o","object":"model","owned_by":"openai"},{"id":"llama-3","object":"model","owned_by":"meta"}]}"#
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/models")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)

        let models = try await client.fetchModels(
            baseURL: URL(string: "http://localhost:8080/v1")!,
            apiKey: nil
        )

        #expect(models.count == 2)
        // Sorted alphabetically by id
        #expect(models[0].id == "gpt-4o")
        #expect(models[1].id == "llama-3")
    }

    @Test func test_fetchModels_sends_auth_header() async throws {
        let responseBody = #"{"object":"list","data":[]}"#
        let session = MockURLProtocol.makeSession { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)

        let models = try await client.fetchModels(
            baseURL: URL(string: "http://localhost:8080/v1")!,
            apiKey: "sk-test"
        )

        #expect(models.isEmpty)
    }

    @Test func test_fetchModels_no_auth_when_nil() async throws {
        let responseBody = #"{"object":"list","data":[]}"#
        let session = MockURLProtocol.makeSession { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)

        _ = try await client.fetchModels(
            baseURL: URL(string: "http://localhost:8080/v1")!,
            apiKey: nil
        )
    }

    @Test func test_fetchModels_handles_http_error() async throws {
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":{"message":"Unauthorized"}}"#.utf8))
        }
        let client = APIClient(session: session)

        await #expect(throws: APIError.self) {
            _ = try await client.fetchModels(
                baseURL: URL(string: "http://localhost:8080/v1")!,
                apiKey: nil
            )
        }
    }

    // MARK: - ModelObject contextLength decoding

    @Test func test_modelObject_decodes_without_contextLength() throws {
        let json = #"{"id":"gpt-4o","object":"model","owned_by":"openai"}"#
        let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
        #expect(model.id == "gpt-4o")
        #expect(model.contextLength == nil)
    }

    @Test func test_modelObject_decodes_context_length() throws {
        let json = #"{"id":"llama-3","object":"model","owned_by":"meta","context_length":131072}"#
        let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
        #expect(model.id == "llama-3")
        #expect(model.contextLength == 131_072)
    }

    @Test func test_modelObject_decodes_max_model_len() throws {
        let json = #"{"id":"qwen-72b","object":"model","owned_by":"vllm","max_model_len":32768}"#
        let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
        #expect(model.id == "qwen-72b")
        #expect(model.contextLength == 32_768)
    }

    @Test func test_modelObject_prefers_context_length_over_max_model_len() throws {
        let json = #"{"id":"m","object":"model","context_length":8192,"max_model_len":4096}"#
        let model = try JSONDecoder().decode(ModelObject.self, from: Data(json.utf8))
        #expect(model.contextLength == 8192)
    }

    @Test func test_fetchModels_carries_contextLength() async throws {
        let responseBody = #"{"object":"list","data":[{"id":"llama","object":"model","owned_by":"meta","context_length":65536}]}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)

        let models = try await client.fetchModels(
            baseURL: URL(string: "http://localhost:8080/v1")!,
            apiKey: nil
        )

        #expect(models.first?.contextLength == 65_536)
    }
}
