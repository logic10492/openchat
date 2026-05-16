import Foundation
import Testing

@testable import OpenChat

@Suite("Agent descriptor")
struct AgentDescriptorTests {
    @Test func test_descriptor_roundTrips_throughJSON() throws {
        let descriptor = AgentDescriptor(
            id: "background.worker.default",
            kind: .backgroundWorker,
            displayName: "Background Worker",
            version: "1.0.0",
            purpose: "Selects background context candidates."
        )

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(AgentDescriptor.self, from: data)

        #expect(decoded == descriptor)
    }

    @Test func test_agentKind_rawValues_areStable() {
        #expect(AgentKind.backgroundWorker.rawValue == "backgroundWorker")
        #expect(AgentKind.director.rawValue == "director")
        #expect(AgentKind.librarian.rawValue == "librarian")
        #expect(AgentKind.reflect.rawValue == "reflect")
        #expect(AgentKind.relationshipUpdater.rawValue == "relationshipUpdater")
        #expect(AgentKind.conversationStateTracker.rawValue == "conversationStateTracker")
    }
}
