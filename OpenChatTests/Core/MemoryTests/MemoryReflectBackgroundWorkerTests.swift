import Foundation
import Testing

@testable import OpenChat

@Suite("Idle memory reflect worker")
struct MemoryReflectBackgroundWorkerTests {
    @Test func test_idleReflectProducesDraftWithoutApplyingToDatabase() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "idle-reflect-card")
        try await database.write { db in try card.insert(db) }
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "idle-memory-a",
                characterCardId: card.id,
                content: "Ava keeps a lantern.",
                memoryType: .relationship,
                importance: 80
            )
        )
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "idle-memory-b",
                characterCardId: card.id,
                content: "The lantern signals rescue.",
                memoryType: .summary,
                importance: 75
            )
        )
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "idle-memory-c",
                characterCardId: card.id,
                content: "Ava waits near the bridge.",
                memoryType: .fact,
                importance: 95
            )
        )

        let assistantContent = #"{"content":"Ava associates lantern light with rescue at the bridge.","type":"summary","basedOn":["idle-memory-c","idle-memory-a","idle-memory-b"],"confidence":0.7,"suggestedAction":"insert_observation"}"#
        let escapedContent = assistantContent
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        let responseBody = #"{"id":"idle-reflect-response","choices":[{"index":0,"message":{"role":"assistant","content":"\#(escapedContent)"},"finish_reason":"stop"}],"usage":null}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(responseBody.utf8))
        }
        let worker = MemoryReflectBackgroundWorker(
            databaseManager: database,
            reflectExecutor: MemoryReflectExecutor(databaseManager: database, apiClient: APIClient(session: session)),
            policy: MemoryReflectBackgroundPolicy(minimumMemories: 3, maximumSourceMemories: 5, minimumInterval: 60)
        )

        let beforeCount = try await database.fetchMemoryCount(characterCardId: card.id)
        let result = try await worker.prepareIdleDraft(
            characterCardId: card.id,
            endpoint: TestHelpers.makeEndpoint(modelName: "reflect-idle-model"),
            now: Date(timeIntervalSince1970: 100)
        )
        let afterCount = try await database.fetchMemoryCount(characterCardId: card.id)

        #expect(result.observation?.content == "Ava associates lantern light with rescue at the bridge.")
        #expect(result.diagnostics?.task == .summarize)
        #expect(result.skippedReason == nil)
        #expect(beforeCount == 3)
        #expect(afterCount == 3)
    }

    @Test func test_idleReflectSkipsWhenTooSoonOrInsufficientMemories() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "idle-reflect-skip-card")
        try await database.write { db in try card.insert(db) }
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "skip-memory-a",
                characterCardId: card.id,
                memoryType: .summary,
                importance: 90
            )
        )

        let worker = MemoryReflectBackgroundWorker(
            databaseManager: database,
            reflectExecutor: MemoryReflectExecutor(databaseManager: database, apiClient: APIClient()),
            policy: MemoryReflectBackgroundPolicy(minimumMemories: 2, maximumSourceMemories: 5, minimumInterval: 60)
        )

        let insufficient = try await worker.prepareIdleDraft(
            characterCardId: card.id,
            endpoint: TestHelpers.makeEndpoint(),
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(insufficient.skippedReason == .insufficientMemories)
    }
}
