import Foundation
import Testing

@testable import OpenChat

@Suite("DatabaseManager+Memory")
struct DatabaseManagerMemoryTests {
    @Test func test_save_and_fetch_memory() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        let entry = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Alice befriended the dragon.")
        try await manager.saveMemory(entry)

        let fetched = try await manager.fetchMemories(characterCardId: card.id)
        #expect(fetched.count == 1)
        #expect(fetched[0].content == "Alice befriended the dragon.")
    }

    @Test func test_fetch_memories_by_type() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        let event = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Battle occurred.", memoryType: .event)
        let fact = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Sky is blue.", memoryType: .fact)
        try await manager.saveMemory(event)
        try await manager.saveMemory(fact)

        let events = try await manager.fetchMemories(characterCardId: card.id, type: .event)
        #expect(events.count == 1)
        #expect(events[0].memoryType == "event")
    }

    @Test func test_fetch_recent_memories_ordered_by_date() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        for i in 0..<5 {
            let entry = MemoryEntryRecord(
                id: UUID().uuidString,
                characterCardId: card.id,
                sourceConversationId: nil,
                content: "Memory \(i)",
                memoryType: "event",
                importance: i,
                createdAt: Date(timeIntervalSinceNow: Double(i) * -60),
                updatedAt: Date(timeIntervalSinceNow: Double(i) * -60)
            )
            try await manager.saveMemory(entry)
        }

        let recent = try await manager.fetchRecentMemories(characterCardId: card.id, limit: 3)
        #expect(recent.count == 3)
        // Most recent first
        #expect(recent[0].content == "Memory 0")
    }

    @Test func test_fetch_memory_count() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        try await manager.saveMemory(TestHelpers.makeMemoryEntry(characterCardId: card.id))
        try await manager.saveMemory(TestHelpers.makeMemoryEntry(characterCardId: card.id))

        let count = try await manager.fetchMemoryCount(characterCardId: card.id)
        #expect(count == 2)
    }

    @Test func test_has_memories_for_conversation() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let conversation = TestHelpers.makeConversation()
        try await manager.write { db in
            try card.insert(db)
            try conversation.insert(db)
        }

        let before = try await manager.hasMemoriesForConversation(conversationId: conversation.id)
        #expect(before == false)

        let entry = TestHelpers.makeMemoryEntry(
            characterCardId: card.id,
            sourceConversationId: conversation.id
        )
        try await manager.saveMemory(entry)

        let after = try await manager.hasMemoriesForConversation(conversationId: conversation.id)
        #expect(after == true)
    }

    @Test func test_delete_memory() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        let entry = TestHelpers.makeMemoryEntry(characterCardId: card.id)
        try await manager.saveMemory(entry)
        try await manager.deleteMemory(id: entry.id)

        let count = try await manager.fetchMemoryCount(characterCardId: card.id)
        #expect(count == 0)
    }

    @Test func test_delete_all_memories() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        try await manager.saveMemory(TestHelpers.makeMemoryEntry(characterCardId: card.id))
        try await manager.saveMemory(TestHelpers.makeMemoryEntry(characterCardId: card.id))

        try await manager.deleteAllMemories(characterCardId: card.id)

        let count = try await manager.fetchMemoryCount(characterCardId: card.id)
        #expect(count == 0)
    }

    @Test func test_fetch_memories_by_ids() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await manager.write { db in try card.insert(db) }

        let entry1 = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "First")
        let entry2 = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Second")
        let entry3 = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Third")
        try await manager.saveMemory(entry1)
        try await manager.saveMemory(entry2)
        try await manager.saveMemory(entry3)

        let fetched = try await manager.fetchMemories(ids: [entry1.id, entry3.id])
        #expect(fetched.count == 2)
        #expect(fetched.contains(where: { $0.content == "First" }))
        #expect(fetched.contains(where: { $0.content == "Third" }))
    }
}
