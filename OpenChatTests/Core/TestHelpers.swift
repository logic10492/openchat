import Foundation
import GRDB

@testable import OpenChat

enum TestHelpers {
    static func makeDatabaseManager() throws -> DatabaseManager {
        try DatabaseManager(dbQueue: DatabaseQueue())
    }

    static func makeEndpoint(
        baseURL: String = "http://localhost:8080/v1",
        apiKey: String? = "test-key",
        modelName: String = "gpt-4o-mini",
        maxContextTokens: Int = 4096
    ) -> APIEndpointConfig {
        APIEndpointConfig(
            baseURL: URL(string: baseURL)!,
            apiKey: apiKey,
            modelName: modelName,
            maxContextTokens: maxContextTokens
        )
    }

    static func makeConversation(
        id: String = UUID().uuidString,
        title: String = "Test Conversation",
        contextStrategy: ContextStrategy = .truncation
    ) -> ConversationRecord {
        ConversationRecord(
            id: id,
            title: title,
            characterCardId: nil,
            apiEndpointId: nil,
            contextStrategy: contextStrategy.rawValue,
            customScenario: nil,
            modelParameters: nil,
            isPinned: false,
            createdAt: .now,
            updatedAt: .now
        )
    }

    static func makeMessage(
        conversationId: String,
        role: String,
        content: String,
        sortOrder: Int,
        isCompressed: Bool = false
    ) -> MessageRecord {
        MessageRecord(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: role,
            content: content,
            tokenCount: TokenCounter.count(content),
            isCompressed: isCompressed,
            originalContent: nil,
            sortOrder: sortOrder,
            createdAt: .now
        )
    }

    static func makeCharacterCard(
        id: String = UUID().uuidString,
        name: String = "Ava",
        systemPrompt: String? = nil,
        scenario: String? = "A quiet tavern in the rain.",
        exampleDialogs: [ChatMessage] = [
            .init(role: "user", content: "Hello"),
            .init(role: "assistant", content: "Hello there.")
        ]
    ) -> CharacterCardRecord {
        return CharacterCardRecord(
            id: id,
            name: name,
            avatar: nil,
            personality: "Kind and observant",
            appearance: "Long silver hair",
            physique: "Lean",
            speechStyle: "Warm",
            backstory: "Raised in a mountain village.",
            systemPrompt: systemPrompt,
            scenario: scenario,
            exampleDialogs: TestJSONFactory.encodedString(exampleDialogs),
            creatorNotes: nil,
            tags: #"["fantasy"]"#,
            createdAt: TestDateFactory.now(),
            updatedAt: TestDateFactory.now()
        )
    }

    static func makeWorldBook(
        id: String = UUID().uuidString,
        name: String = "Lorebook",
        isEnabled: Bool = true
    ) -> WorldBookRecord {
        WorldBookRecord(
            id: id,
            name: name,
            description: "World notes",
            isEnabled: isEnabled,
            createdAt: .now,
            updatedAt: .now
        )
    }

    static func makeWorldBookEntry(
        worldBookId: String,
        id: String = UUID().uuidString,
        title: String = "Dragon",
        keywords: [String] = ["dragon"],
        priority: Int = 50,
        position: WorldBookEntryPosition = .beforeHistory,
        content: String = "Dragons guard the northern pass."
    ) -> WorldBookEntryRecord {
        return WorldBookEntryRecord(
            id: id,
            worldBookId: worldBookId,
            title: title,
            content: content,
            keywords: TestJSONFactory.encodedString(keywords) ?? "[]",
            priority: priority,
            isEnabled: true,
            position: position.rawValue,
            createdAt: TestDateFactory.now(),
            updatedAt: TestDateFactory.now()
        )
    }

    static func makeMemoryEntry(
        id: String = UUID().uuidString,
        characterCardId: String,
        sourceConversationId: String? = nil,
        content: String = "The hero saved the village.",
        memoryType: MemoryType = .event,
        importance: Int = 5
    ) -> MemoryEntryRecord {
        MemoryEntryRecord(
            id: id,
            characterCardId: characterCardId,
            sourceConversationId: sourceConversationId,
            content: content,
            memoryType: memoryType.rawValue,
            importance: importance,
            createdAt: TestDateFactory.now(),
            updatedAt: TestDateFactory.now()
        )
    }
}
