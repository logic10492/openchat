import Foundation
import Testing

@testable import OpenChat

// MARK: - ResponsesAPIRequest Tests

@Suite("Responses API request")
struct ResponsesAPIRequestTests {
    @Test func test_system_messages_extracted_to_instructions() throws {
        let messages: [ChatMessage] = [
            .init(role: "system", content: "You are helpful."),
            .init(role: "user", content: "Hello"),
            .init(role: "assistant", content: "Hi there"),
        ]
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(messages: messages, endpoint: endpoint, parameters: ModelParameters(), stream: false)

        #expect(request.instructions == "You are helpful.")
        #expect(request.input.count == 2)
        #expect(request.input[0].role == "user")
        #expect(request.input[1].role == "assistant")
    }

    @Test func test_multiple_system_messages_joined() throws {
        let messages: [ChatMessage] = [
            .init(role: "system", content: "Line 1"),
            .init(role: "system", content: "Line 2"),
            .init(role: "user", content: "Hi"),
        ]
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(messages: messages, endpoint: endpoint, parameters: ModelParameters(), stream: false)

        #expect(request.instructions == "Line 1\nLine 2")
        #expect(request.input.count == 1)
    }

    @Test func test_no_system_messages_gives_nil_instructions() throws {
        let messages: [ChatMessage] = [
            .init(role: "user", content: "Hello"),
        ]
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(messages: messages, endpoint: endpoint, parameters: ModelParameters(), stream: false)

        #expect(request.instructions == nil)
        #expect(request.input.count == 1)
    }

    @Test func test_store_always_false() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(messages: [], endpoint: endpoint, parameters: ModelParameters(), stream: false)

        #expect(request.store == false)
    }

    @Test func test_encoding_uses_snake_case() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(
            messages: [.init(role: "user", content: "Hi")],
            endpoint: endpoint,
            parameters: ModelParameters(maxTokens: 100),
            stream: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["top_p"] != nil)
        #expect(json["max_output_tokens"] as? Int == 100)
        #expect(json["store"] as? Bool == false)
        // frequency_penalty and presence_penalty should NOT appear
        #expect(json["frequency_penalty"] == nil)
        #expect(json["presence_penalty"] == nil)
    }

    @Test func test_unsupported_params_stripped() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let params = ModelParameters(frequencyPenalty: 0.5, presencePenalty: 0.3, stop: ["END"])
        let request = ResponsesAPIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        // The request should not encode frequency_penalty, presence_penalty, stop at all
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["frequency_penalty"] == nil)
        #expect(json["presence_penalty"] == nil)
        #expect(json["stop"] == nil)
    }

    @Test func test_input_omits_reasoning_content_by_default() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let request = ResponsesAPIRequest(
            messages: [
                .init(
                    role: "assistant",
                    content: "Visible character reply.",
                    reasoningContent: "Private role-perspective thinking."
                ),
            ],
            endpoint: endpoint,
            parameters: ModelParameters(),
            stream: false
        )

        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])

        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "assistant")
        #expect(input[0]["content"] as? String == "Visible character reply.")
        #expect(input[0]["reasoning_content"] == nil)
    }
}

// MARK: - ResponsesAPIResponse Tests

@Suite("Responses API response")
struct ResponsesAPIResponseTests {
    @Test func test_decode_completed_response() throws {
        let json = """
        {
            "id": "resp_123",
            "status": "completed",
            "output": [{
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "Hello world"}]
            }],
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
        }
        """
        let response = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))

        #expect(response.id == "resp_123")
        #expect(response.status == "completed")
        #expect(response.output.count == 1)
        #expect(response.output[0].type == "message")
        #expect(response.output[0].content?.first?.text == "Hello world")
        #expect(response.usage?.inputTokens == 10)
        #expect(response.usage?.outputTokens == 5)
    }

    @Test func test_toCompletionResponse_conversion() throws {
        let json = """
        {
            "id": "resp_456",
            "status": "completed",
            "output": [
                {"id": "rs_1", "type": "reasoning", "content": []},
                {
                    "id": "msg_1",
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "output_text", "text": "Hi there!"}]
                }
            ],
            "usage": {"input_tokens": 20, "output_tokens": 10, "total_tokens": 30}
        }
        """
        let responseObj = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))
        let completion = responseObj.toCompletionResponse()

        #expect(completion.id == "resp_456")
        #expect(completion.choices.count == 1)
        #expect(completion.choices[0].message.role == "assistant")
        #expect(completion.choices[0].message.content == "Hi there!")
        #expect(completion.choices[0].finishReason == "stop")
        #expect(completion.usage?.promptTokens == 20)
        #expect(completion.usage?.completionTokens == 10)
        #expect(completion.usage?.totalTokens == 30)
    }

    @Test func test_toCompletionResponse_skips_non_message_output() throws {
        let json = """
        {
            "id": "resp_789",
            "status": "completed",
            "output": [
                {"id": "rs_1", "type": "reasoning", "content": []}
            ],
            "usage": null
        }
        """
        let responseObj = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))
        let completion = responseObj.toCompletionResponse()

        #expect(completion.choices[0].message.content == "")
    }
}

// MARK: - SSE Parser Typed Events Tests

@Suite("SSE parser typed events")
struct SSEParserTypedEventsTests {
    @Test func test_parse_event_type() async throws {
        let payload = """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hello"}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"r1","status":"completed"}}

        """

        let stream = AsyncStream<UInt8> { continuation in
            for byte in payload.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var events: [SSEEvent] = []
        for try await event in SSEStreamParser.parse(sequence: stream) {
            events.append(event)
        }

        #expect(events.count == 2)
        #expect(events[0].eventType == "response.output_text.delta")
        #expect(events[0].data.contains("Hello"))
        #expect(events[1].eventType == "response.completed")
    }

    @Test func test_backward_compatible_no_event_type() async throws {
        let payload = """
        data: {"id":"1","choices":[{"index":0,"delta":{"content":"Hi"}}]}

        data: [DONE]
        """

        let stream = AsyncStream<UInt8> { continuation in
            for byte in payload.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var events: [SSEEvent] = []
        for try await event in SSEStreamParser.parse(sequence: stream) {
            events.append(event)
        }

        #expect(events.count == 1)
        #expect(events[0].eventType == nil)
        #expect(events[0].data.contains("Hi"))
    }

    @Test func test_event_type_resets_between_events() async throws {
        let payload = """
        event: response.output_text.delta
        data: {"delta":"A"}

        data: {"plain":"B"}

        """

        let stream = AsyncStream<UInt8> { continuation in
            for byte in payload.utf8 {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        var events: [SSEEvent] = []
        for try await event in SSEStreamParser.parse(sequence: stream) {
            events.append(event)
        }

        #expect(events.count == 2)
        #expect(events[0].eventType == "response.output_text.delta")
        #expect(events[1].eventType == nil)
    }
}

// MARK: - APIClient Responses Mode Tests

@Suite("APIClient responses mode")
struct APIClientResponsesModeTests {
    @Test func test_sendMessage_responses_mode_posts_to_responses_endpoint() async throws {
        let responseBody = """
        {
            "id": "resp_abc",
            "status": "completed",
            "output": [{
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "Hello from responses!"}]
            }],
            "usage": {"input_tokens": 5, "output_tokens": 3, "total_tokens": 8}
        }
        """
        let session = MockURLProtocol.makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

            // Verify request body has instructions extracted from system message
            if let httpBody = request.httpBody,
               let body = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] {
                #expect(body["instructions"] as? String == "Be helpful.")
                if let input = body["input"] as? [[String: Any]] {
                    #expect(input.count == 1)
                    #expect(input[0]["role"] as? String == "user")
                }
                #expect(body["store"] as? Bool == false)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let client = APIClient(session: session)

        let response = try await client.sendMessage(
            messages: [
                .init(role: "system", content: "Be helpful."),
                .init(role: "user", content: "Hello"),
            ],
            endpoint: endpoint,
            parameters: ModelParameters()
        )

        #expect(response.choices.first?.message.content == "Hello from responses!")
        #expect(response.usage?.promptTokens == 5)
        #expect(response.usage?.completionTokens == 3)
    }

    @Test func test_streamMessage_responses_mode_yields_deltas() async throws {
        let payload = """
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_1","status":"in_progress"}}

        event: response.output_item.added
        data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Hel"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"lo"}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":3,"output_tokens":2,"total_tokens":5}}}

        """
        let session = MockURLProtocol.makeSession { request in
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/responses")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let client = APIClient(session: session)

        var deltas: [StreamDelta] = []
        for try await delta in client.streamMessage(
            messages: [.init(role: "user", content: "Hi")],
            endpoint: endpoint,
            parameters: ModelParameters()
        ) {
            deltas.append(delta)
        }

        #expect(deltas.count == 3)
        #expect(deltas[0].content == "Hel")
        #expect(deltas[0].finishReason == nil)
        #expect(deltas[1].content == "lo")
        #expect(deltas[1].finishReason == nil)
        #expect(deltas[2].finishReason == "stop")
    }

    @Test func test_streamMessage_responses_mode_yields_reasoning_delta() async throws {
        let payload = """
        event: response.reasoning.delta
        data: {"type":"response.reasoning.delta","delta":"Thinking..."}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Answer"}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_1","status":"completed"}}

        """
        let session = MockURLProtocol.makeSession { request in
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/responses")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let client = APIClient(session: session)

        var deltas: [StreamDelta] = []
        for try await delta in client.streamMessage(
            messages: [.init(role: "user", content: "Hi")],
            endpoint: endpoint,
            parameters: ModelParameters()
        ) {
            deltas.append(delta)
        }

        #expect(deltas[0].content == "")
        #expect(deltas[0].reasoningContent == "Thinking...")
        #expect(deltas[1].content == "Answer")
        #expect(deltas[1].reasoningContent == nil)
        #expect(deltas[2].finishReason == "stop")
    }

    @Test func test_sendMessage_responses_mode_appends_responses_to_baseURL_without_forcing_v1() async throws {
        let responseBody = """
        {
            "id": "resp_abc",
            "status": "completed",
            "output": [{
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": "Hello"}]
            }],
            "usage": null
        }
        """
        let session = MockURLProtocol.makeSession { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/responses")

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint(baseURL: "https://api.deepseek.com", apiMode: .responses)
        let client = APIClient(session: session)

        _ = try await client.sendMessage(
            messages: [.init(role: "user", content: "Hello")],
            endpoint: endpoint,
            parameters: ModelParameters()
        )
    }

    @Test func test_streamMessage_responses_mode_handles_failure() async throws {
        let payload = """
        event: response.failed
        data: {"type":"response.failed","response":{"id":"resp_1","status":"failed","error":{"code":"server_error","message":"Boom"}}}

        """
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let client = APIClient(session: session)

        await #expect(throws: APIError.self) {
            for try await _ in client.streamMessage(
                messages: [.init(role: "user", content: "Hi")],
                endpoint: endpoint,
                parameters: ModelParameters()
            ) {}
        }
    }
}

// MARK: - ModelParameters forAPIMode Tests

@Suite("ModelParameters API mode filtering")
struct ModelParametersAPIModeTests {
    @Test func test_chatCompletions_mode_preserves_all_params() {
        let params = ModelParameters(
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 200,
            frequencyPenalty: 0.5,
            presencePenalty: 0.3,
            stop: ["END"]
        )
        let filtered = params.forAPIMode(.chatCompletions)

        #expect(filtered.frequencyPenalty == 0.5)
        #expect(filtered.presencePenalty == 0.3)
        #expect(filtered.stop == ["END"])
    }

    @Test func test_responses_mode_clears_unsupported_params() {
        let params = ModelParameters(
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 200,
            frequencyPenalty: 0.5,
            presencePenalty: 0.3,
            stop: ["END"]
        )
        let filtered = params.forAPIMode(.responses)

        #expect(filtered.temperature == 0.7)
        #expect(filtered.topP == 0.9)
        #expect(filtered.maxTokens == 200)
        #expect(filtered.frequencyPenalty == 0.0)
        #expect(filtered.presencePenalty == 0.0)
        #expect(filtered.stop == nil)
    }
}
