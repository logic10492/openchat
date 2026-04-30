import Foundation
import Testing

@testable import OpenChat

private final class CompressionSummarizerRequestCapture: @unchecked Sendable {
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

private extension URLRequest {
    func compressionTestBodyData() throws -> Data {
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

@Suite("Compression summarizer")
struct CompressionSummarizerTests {
    @Test func test_summarize_sends_checkpoint_prompt_and_source_messages() async throws {
        let responseBody = #"{"id":"1","choices":[{"index":0,"message":{"role":"assistant","content":"summary text"},"finish_reason":"stop"}]}"#
        let capture = CompressionSummarizerRequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.compressionTestBodyData()
            capture.store(try JSONDecoder().decode(APIRequest.self, from: body))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let apiClient = APIClient(session: session)
        let endpoint = TestHelpers.makeEndpoint(maxContextTokens: 4096)
        let messages = [
            TestHelpers.makeMessage(conversationId: "conv", role: "user", content: "old user", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: "conv", role: "assistant", content: "old reply", sortOrder: 2)
        ]

        let summary = try await CompressionSummarizer(apiClient: apiClient, endpoint: endpoint)
            .summarize(previousSummary: nil, messages: messages, maxTokens: 128)

        let request = try #require(capture.load())
        #expect(summary == "summary text")
        #expect(request.messages.first?.role == "system")
        #expect(request.messages.first?.content.contains("CONTEXT CHECKPOINT COMPACTION") == true)
        #expect(request.messages.last?.content.contains("user: old user") == true)
        #expect(request.messages.last?.content.contains("assistant: old reply") == true)
    }
}
