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

    @Test func test_fetch_recent_high_value_memories_filters_noise_and_prioritizes_type() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-high-value-db")
        try await manager.write { db in try card.insert(db) }

        let now = Date(timeIntervalSince1970: 1_000)
        let noise = MemoryEntryRecord(
            id: "noise",
            characterCardId: card.id,
            sourceConversationId: nil,
            content: "Recent low-value event",
            memoryType: MemoryType.event.rawValue,
            importance: 10,
            createdAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(60)
        )
        let importantFact = MemoryEntryRecord(
            id: "important-fact",
            characterCardId: card.id,
            sourceConversationId: nil,
            content: "Important fact",
            memoryType: MemoryType.fact.rawValue,
            importance: 90,
            createdAt: now.addingTimeInterval(30),
            updatedAt: now.addingTimeInterval(30)
        )
        let summary = MemoryEntryRecord(
            id: "summary",
            characterCardId: card.id,
            sourceConversationId: nil,
            content: "Summary memory",
            memoryType: MemoryType.summary.rawValue,
            importance: 20,
            createdAt: now,
            updatedAt: now
        )
        let relationship = MemoryEntryRecord(
            id: "relationship",
            characterCardId: card.id,
            sourceConversationId: nil,
            content: "Relationship memory",
            memoryType: MemoryType.relationship.rawValue,
            importance: 30,
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-30)
        )
        try await manager.saveMemory(noise)
        try await manager.saveMemory(importantFact)
        try await manager.saveMemory(summary)
        try await manager.saveMemory(relationship)

        let highValue = try await manager.fetchRecentHighValueMemories(
            characterCardId: card.id,
            limit: 5
        )

        #expect(highValue.map(\.id) == ["relationship", "summary", "important-fact"])
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

    @Test func test_save_memory_entry_links_dedupes_and_fetches_by_from() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source-a", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation-a", characterCardId: card.id)
        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try observation.insert(db)
        }

        let firstLink = MemoryEntryLinkRecord(
            id: "link-a",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .summarizes,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let duplicateLink = MemoryEntryLinkRecord(
            id: "link-a-duplicate",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .summarizes,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        try await manager.saveMemoryEntryLinks([firstLink, duplicateLink])
        try await manager.saveMemoryEntryLinks([
            MemoryEntryLinkRecord(
                id: "link-a-second-save-duplicate",
                fromMemoryEntryId: observation.id,
                toMemoryEntryId: source.id,
                relation: .summarizes,
                createdAt: Date(timeIntervalSince1970: 3)
            )
        ])

        let fetched = try await manager.fetchMemoryEntryLinks(fromMemoryEntryId: observation.id)
        #expect(fetched == [firstLink])
        #expect(fetched.first?.relationValue == .summarizes)
    }

    @Test func test_fetch_memory_entry_links_by_to() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source-b", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation-b", characterCardId: card.id)
        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try observation.insert(db)
        }
        let link = MemoryEntryLinkRecord(
            id: "link-b",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .reinforces,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        try await manager.saveMemoryEntryLinks([link])

        let fetched = try await manager.fetchMemoryEntryLinks(toMemoryEntryId: source.id)
        #expect(fetched == [link])
    }

    @Test func test_fetch_memory_entry_links_by_memory_entry_ids_returns_from_and_to_matches() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source-c", characterCardId: card.id)
        let duplicateSource = TestHelpers.makeMemoryEntry(id: "memory-link-source-d", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation-c", characterCardId: card.id)
        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try duplicateSource.insert(db)
            try observation.insert(db)
        }
        let summarizes = MemoryEntryLinkRecord(
            id: "link-c",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .summarizes,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let duplicates = MemoryEntryLinkRecord(
            id: "link-d",
            fromMemoryEntryId: duplicateSource.id,
            toMemoryEntryId: observation.id,
            relation: .duplicates,
            createdAt: Date(timeIntervalSince1970: 5)
        )

        try await manager.saveMemoryEntryLinks([summarizes, duplicates])

        let fetched = try await manager.fetchMemoryEntryLinks(memoryEntryIds: [source.id, observation.id])
        #expect(fetched == [summarizes, duplicates])
    }

    @Test func test_invalid_memory_entry_link_relation_is_not_written() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source-invalid", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation-invalid", characterCardId: card.id)
        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try observation.insert(db)
        }
        let invalidLink = MemoryEntryLinkRecord(
            id: "link-invalid",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: "conflicts",
            createdAt: Date(timeIntervalSince1970: 6)
        )

        await #expect(throws: MemoryEntryLinkValidationError.invalidRelation("conflicts")) {
            try await manager.saveMemoryEntryLinks([invalidLink])
        }

        let fetched = try await manager.fetchMemoryEntryLinks(memoryEntryIds: [source.id, observation.id])
        #expect(fetched.isEmpty)
    }
}
