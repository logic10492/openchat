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
        let request = try makeRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: false)

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

    func streamMessage(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages, endpoint: endpoint, parameters: parameters, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response: response)

                    for try await event in SSEStreamParser.parse(bytes: bytes) {
                        let chunk: ChatCompletionChunk
                        do {
                            chunk = try decoder.decode(ChatCompletionChunk.self, from: Data(event.data.utf8))
                        } catch {
                            throw APIError.decodingError(underlying: error)
                        }
                        for choice in chunk.choices {
                            let content = choice.delta.content ?? ""
                            if !content.isEmpty || choice.finishReason != nil {
                                continuation.yield(StreamDelta(content: content, finishReason: choice.finishReason))
                            }
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

    private func makeRequest(
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
