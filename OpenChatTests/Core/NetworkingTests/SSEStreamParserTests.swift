import Foundation
import Testing

@testable import OpenChat

@Suite("SSE parser")
struct SSEStreamParserTests {
    @Test func test_parse_emits_events_and_stops_on_done() async throws {
        let payload = """
        : keep-alive
        data: {"id":"1","choices":[{"index":0,"delta":{"content":"Hel"}}]}

        data: {"id":"1","choices":[{"index":0,"delta":{"content":"lo"},"finish_reason":"stop"}]}

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

        #expect(events.count == 2)
        #expect(events[0].data.contains("Hel"))
        #expect(events[1].data.contains("lo"))
    }
}
