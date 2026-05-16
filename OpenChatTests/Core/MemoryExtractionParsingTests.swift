import Foundation
import Testing

@testable import OpenChat

@Suite("Memory extraction parsing")
struct MemoryExtractionParsingTests {

    // MARK: - ExtractedMemory decoding

    @Test func test_decode_standard_format() throws {
        let json = """
        [
          {"content": "Player saved the elf", "type": "event", "importance": 85}
        ]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result.count == 1)
        #expect(result[0].content == "Player saved the elf")
        #expect(result[0].resolvedType == .event)
        #expect(result[0].resolvedImportance == 85)
    }

    @Test func test_decode_uppercase_type_falls_back() throws {
        let json = """
        [{"content": "Something happened", "type": "Event", "importance": 70}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedType == .event)
    }

    @Test func test_decode_unknown_type_defaults_to_event() throws {
        let json = """
        [{"content": "Unknown type", "type": "personality", "importance": 60}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedType == .event)
    }

    @Test func test_decode_missing_type_defaults_to_event() throws {
        let json = """
        [{"content": "No type field", "importance": 50}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedType == .event)
    }

    @Test func test_decode_string_importance() throws {
        let json = """
        [{"content": "String importance", "type": "fact", "importance": "85"}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedImportance == 85)
        #expect(result[0].resolvedType == .fact)
    }

    @Test func test_decode_missing_importance_defaults_to_50() throws {
        let json = """
        [{"content": "No importance", "type": "summary"}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedImportance == 50)
    }

    @Test func test_decode_importance_clamped_to_100() throws {
        let json = """
        [{"content": "Over 100", "type": "event", "importance": 150}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].resolvedImportance == 100)
    }

    @Test func test_decode_extra_fields_ignored() throws {
        let json = """
        [{"content": "Extra fields", "type": "event", "importance": 70, "source": "dialogue", "tags": ["combat"]}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result.count == 1)
        #expect(result[0].content == "Extra fields")
    }

    @Test func test_decode_all_valid_types() throws {
        for typeName in ["event", "fact", "relationship", "summary"] {
            let json = """
            [{"content": "Test", "type": "\(typeName)", "importance": 50}]
            """
            let data = Data(json.utf8)
            let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
            #expect(result[0].resolvedType == MemoryType(rawValue: typeName))
        }
    }

    // MARK: - latestMemoryDate

    @Test func test_latestMemoryDate_returns_nil_when_no_memories() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let date = try await db.latestMemoryDate(conversationId: "nonexistent")
        #expect(date == nil)
    }

    @Test func test_latestMemoryDate_returns_latest() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await db.write { db in try card.insert(db) }

        let conv = TestHelpers.makeConversation()
        try await db.saveConversation(conv)

        let early = MemoryEntryRecord(
            id: UUID().uuidString,
            characterCardId: card.id,
            sourceConversationId: conv.id,
            content: "Early memory",
            memoryType: "event",
            importance: 50,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        let late = MemoryEntryRecord(
            id: UUID().uuidString,
            characterCardId: card.id,
            sourceConversationId: conv.id,
            content: "Late memory",
            memoryType: "fact",
            importance: 80,
            createdAt: Date(timeIntervalSince1970: 2000),
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        try await db.saveMemory(early)
        try await db.saveMemory(late)

        let result = try await db.latestMemoryDate(conversationId: conv.id)
        #expect(result == Date(timeIntervalSince1970: 2000))
    }

    // MARK: - StreamDelta usage

    @Test func test_streamDelta_carries_usage() {
        let usage = StreamUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        let delta = StreamDelta(content: "", finishReason: "stop", usage: usage)
        #expect(delta.usage?.promptTokens == 100)
        #expect(delta.usage?.completionTokens == 50)
    }

    @Test func test_streamDelta_default_nil_usage() {
        let delta = StreamDelta(content: "hello", finishReason: nil)
        #expect(delta.usage == nil)
    }

    // MARK: - v2 field decoding

    @Test func test_decode_v2_full_fields() throws {
        let json = """
        [
          {
            "content": "Player befriended the dragon",
            "type": "relationship",
            "importance": 85,
            "sourceStartSortOrder": 10,
            "sourceEndSortOrder": 12,
            "sourceMessageIds": ["msg-1", "msg-2"],
            "confidence": 0.92,
            "tags": ["relationship", "dragon"],
            "dedupeKey": "player-dragon-friend",
            "action": "insert"
          }
        ]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result.count == 1)
        #expect(result[0].content == "Player befriended the dragon")
        #expect(result[0].resolvedType == .relationship)
        #expect(result[0].resolvedImportance == 85)
        #expect(result[0].sourceStartSortOrder == 10)
        #expect(result[0].sourceEndSortOrder == 12)
        #expect(result[0].sourceMessageIds == ["msg-1", "msg-2"])
        #expect(result[0].confidence == 0.92)
        #expect(result[0].tags == ["relationship", "dragon"])
        #expect(result[0].dedupeKey == "player-dragon-friend")
        #expect(result[0].action == .insert)
    }

    @Test func test_decode_v2_action_reinforce() throws {
        let json = """
        [{"content": "Reinforced fact", "type": "fact", "importance": 70, "action": "reinforce"}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].action == .reinforce)
    }

    @Test func test_decode_v2_action_skip() throws {
        let json = """
        [{"content": "Skip me", "type": "event", "importance": 50, "action": "skip"}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].action == .skip)
    }

    @Test func test_decode_v2_missing_optional_fields_defaults() throws {
        let json = """
        [{"content": "Minimal v2", "type": "event", "importance": 60}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].sourceStartSortOrder == nil)
        #expect(result[0].sourceEndSortOrder == nil)
        #expect(result[0].sourceMessageIds.isEmpty)
        #expect(result[0].confidence == nil)
        #expect(result[0].tags.isEmpty)
        #expect(result[0].dedupeKey == nil)
        #expect(result[0].action == nil)
    }

    @Test func test_decode_v2_confidence_clamped_by_provenance_not_by_decoder() throws {
        let json = """
        [{"content": "Overconfident", "type": "event", "importance": 50, "confidence": 1.5}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].confidence == 1.5)
    }

    @Test func test_decode_v1_still_compatible() throws {
        let json = """
        [{"content": "Legacy memory", "type": "fact", "importance": 80}]
        """
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode([ExtractedMemory].self, from: data)
        #expect(result[0].content == "Legacy memory")
        #expect(result[0].resolvedType == .fact)
        #expect(result[0].resolvedImportance == 80)
        #expect(result[0].action == nil)
    }

    // MARK: - Provenance record CRUD

    @Test func test_save_and_fetch_memory_provenance() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await db.write { db in try card.insert(db) }

        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)
        try await db.saveMemory(memory)

        let provenance = MemoryEntryProvenanceRecord(
            memoryEntryId: memory.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 3,
            sourceMessageIds: ["m1", "m2"],
            extractionModel: "gpt-4o",
            extractionPromptVersion: "v2",
            confidence: 0.85,
            dedupeKey: "key-1",
            tags: ["event", "combat"],
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveMemoryProvenance(provenance)

        let fetched = try await db.fetchMemoryProvenance(memoryEntryId: memory.id)
        #expect(fetched != nil)
        #expect(fetched?.memoryEntryId == memory.id)
        #expect(fetched?.sourceStartSortOrder == 1)
        #expect(fetched?.sourceEndSortOrder == 3)
        #expect(fetched?.decodedSourceMessageIds == ["m1", "m2"])
        #expect(fetched?.extractionModel == "gpt-4o")
        #expect(fetched?.extractionPromptVersion == "v2")
        #expect(fetched?.confidence == 0.85)
        #expect(fetched?.dedupeKey == "key-1")
        #expect(fetched?.decodedTags == ["event", "combat"])
    }

    @Test func test_fetch_memory_provenance_returns_nil_for_old_memory() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await db.write { db in try card.insert(db) }

        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)
        try await db.saveMemory(memory)

        let fetched = try await db.fetchMemoryProvenance(memoryEntryId: memory.id)
        #expect(fetched == nil)
    }

    @Test func test_delete_memory_provenance() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        try await db.write { db in try card.insert(db) }

        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)
        try await db.saveMemory(memory)

        let provenance = MemoryEntryProvenanceRecord(
            memoryEntryId: memory.id,
            extractionPromptVersion: "v2",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await db.saveMemoryProvenance(provenance)
        try await db.deleteMemoryProvenance(memoryEntryId: memory.id)

        let fetched = try await db.fetchMemoryProvenance(memoryEntryId: memory.id)
        #expect(fetched == nil)
    }
}
