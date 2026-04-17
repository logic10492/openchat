import Foundation

final class APIClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func sendMessage(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) async throws -> ChatCompletionResponse {
        switch endpoint.apiMode {
        case .chatCompletions:
            return try await sendChatCompletions(messages: messages, endpoint: endpoint, parameters: parameters)
        case .responses:
            return try await sendResponses(messages: messages, endpoint: endpoint, parameters: parameters)
        }
    }

    func fetchModels(baseURL: URL, apiKey: String?) async throws -> [ModelObject] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, body: data)
            do {
                let result = try decoder.decode(ModelsListResponse.self, from: data)
                return result.data.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
            } catch {
                throw APIError.decodingError(underlying: error)
            }
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    func streamMessage(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        switch endpoint.apiMode {
        case .chatCompletions:
            return streamChatCompletions(messages: messages, endpoint: endpoint, parameters: parameters)
        case .responses:
            return streamResponses(messages: messages, endpoint: endpoint, parameters: parameters)
        }
    }

    // MARK: - Chat Completions

    private func sendChatCompletions(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) async throws -> ChatCompletionResponse {
        let request = try makeChatCompletionsRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: false)

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, body: data)
            do {
                return try decoder.decode(ChatCompletionResponse.self, from: data)
            } catch {
                throw APIError.decodingError(underlying: error)
            }
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    private func streamChatCompletions(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeChatCompletionsRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validate(response: response)

                    for try await event in SSEStreamParser.parse(bytes: bytes) {
                        let chunk: ChatCompletionChunk
                        do {
                            chunk = try self.decoder.decode(ChatCompletionChunk.self, from: Data(event.data.utf8))
                        } catch {
                            throw APIError.decodingError(underlying: error)
                        }

                        // Usage-only chunk (stream_options: include_usage)
                        let streamUsage = chunk.usage.map {
                            StreamUsage(
                                promptTokens: $0.promptTokens,
                                completionTokens: $0.completionTokens,
                                totalTokens: $0.totalTokens,
                                reasoningTokens: $0.completionTokensDetails?.reasoningTokens ?? 0
                            )
                        }

                        for choice in chunk.choices {
                            let content = choice.delta.content ?? ""
                            let reasoning = choice.delta.reasoningContent
                            if !content.isEmpty || reasoning != nil || choice.finishReason != nil {
                                continuation.yield(StreamDelta(
                                    content: content,
                                    reasoningContent: reasoning,
                                    finishReason: choice.finishReason,
                                    usage: streamUsage
                                ))
                            }
                        }

                        // Final chunk may have usage but empty choices
                        if chunk.choices.isEmpty, let usage = streamUsage {
                            continuation.yield(StreamDelta(content: "", finishReason: nil, usage: usage))
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: APIError.cancelled)
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: APIError.networkError(underlying: error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeChatCompletionsRequest(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters,
        stream: Bool
    ) throws -> URLRequest {
        let url = endpoint.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if let apiKey = endpoint.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = APIRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: stream)
        do {
            request.httpBody = try encoder.encode(body)
            return request
        } catch {
            throw APIError.decodingError(underlying: error)
        }
    }

    // MARK: - Responses API

    private func sendResponses(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) async throws -> ChatCompletionResponse {
        let request = try makeResponsesRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: false)

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response, body: data)
            do {
                let responseObject = try decoder.decode(ResponseObject.self, from: data)
                return responseObject.toCompletionResponse()
            } catch {
                throw APIError.decodingError(underlying: error)
            }
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    private func streamResponses(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeResponsesRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: true)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try self.validate(response: response)

                    for try await event in SSEStreamParser.parse(bytes: bytes) {
                        guard let eventType = event.eventType else { continue }

                        switch eventType {
                        case "response.output_text.delta":
                            let delta: ResponseOutputTextDelta
                            do {
                                delta = try self.decoder.decode(ResponseOutputTextDelta.self, from: Data(event.data.utf8))
                            } catch {
                                throw APIError.decodingError(underlying: error)
                            }
                            if !delta.delta.isEmpty {
                                continuation.yield(StreamDelta(content: delta.delta, finishReason: nil))
                            }

                        case "response.reasoning.delta":
                            let delta: ResponseReasoningDelta
                            do {
                                delta = try self.decoder.decode(ResponseReasoningDelta.self, from: Data(event.data.utf8))
                            } catch {
                                throw APIError.decodingError(underlying: error)
                            }
                            if !delta.delta.isEmpty {
                                continuation.yield(StreamDelta(content: "", reasoningContent: delta.delta, finishReason: nil))
                            }

                        case "response.completed":
                            let completedEvent = try? self.decoder.decode(ResponseCompletedEvent.self, from: Data(event.data.utf8))
                            let usage = completedEvent?.response.usage.map {
                                StreamUsage(promptTokens: $0.inputTokens, completionTokens: $0.outputTokens, totalTokens: $0.totalTokens)
                            }
                            continuation.yield(StreamDelta(content: "", finishReason: "stop", usage: usage))
                            continuation.finish()
                            return

                        case "response.failed":
                            let body = event.data
                            throw APIError.streamParsingError("Response failed: \(body)")

                        case "response.incomplete":
                            continuation.yield(StreamDelta(content: "", finishReason: "length"))
                            continuation.finish()
                            return

                        default:
                            continue
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: APIError.cancelled)
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: APIError.networkError(underlying: error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func makeResponsesRequest(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters,
        stream: Bool
    ) throws -> URLRequest {
        let url = endpoint.baseURL.appendingPathComponent("responses")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        if let apiKey = endpoint.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = ResponsesAPIRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: stream)
        do {
            request.httpBody = try encoder.encode(body)
            return request
        } catch {
            throw APIError.decodingError(underlying: error)
        }
    }

    private func validate(response: URLResponse, body: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.streamParsingError("Missing HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = body.flatMap { String(data: $0, encoding: .utf8) }
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
        }
    }
}
