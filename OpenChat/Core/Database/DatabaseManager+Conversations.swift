import Foundation
import GRDB

extension DatabaseManager {
    func fetchConversations() async throws -> [ConversationRecord] {
        try await read { db in
            try ConversationRecord
                .order(Column("isPinned").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchConversation(id: String?) async throws -> ConversationRecord? {
        guard let id else { return nil }
        return try await read { db in
            try ConversationRecord.fetchOne(db, key: id)
        }
    }

    func saveConversation(_ conversation: ConversationRecord) async throws {
        try await write { db in
            try conversation.save(db)
        }
    }

    func deleteConversation(id: String) async throws {
        try await write { db in
            _ = try ConversationRecord.deleteOne(db, key: id)
        }
    }

    func fetchMessages(conversationId: String) async throws -> [MessageRecord] {
        try await read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    func fetchRecentMessages(
        conversationId: String,
        limit: Int
    ) async throws -> [MessageRecord] {
        let normalizedLimit = max(limit, 0)
        guard normalizedLimit > 0 else { return [] }
        return try await read { db in
            let records = try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("sortOrder").desc)
                .limit(normalizedLimit)
                .fetchAll(db)
            return Array(records.reversed())
        }
    }

    func fetchMessages(
        conversationId: String,
        beforeSortOrder sortOrder: Int,
        limit: Int
    ) async throws -> [MessageRecord] {
        let normalizedLimit = max(limit, 0)
        guard normalizedLimit > 0 else { return [] }
        return try await read { db in
            let records = try MessageRecord
                .filter(Column("conversationId") == conversationId && Column("sortOrder") < sortOrder)
                .order(Column("sortOrder").desc)
                .limit(normalizedLimit)
                .fetchAll(db)
            return Array(records.reversed())
        }
    }

    func saveMessage(_ message: MessageRecord) async throws {
        try await write { db in
            try message.save(db)
            _ = try ConversationRecord
                .filter(Column("id") == message.conversationId)
                .updateAll(db, Column("updatedAt").set(to: message.createdAt))
        }
    }

    func deleteMessage(id: String) async throws {
        try await write { db in
            _ = try MessageRecord.deleteOne(db, key: id)
        }
    }

    func deleteMessages(
        conversationId: String,
        afterSortOrder: Int
    ) async throws {
        try await write { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId && Column("sortOrder") > afterSortOrder)
                .deleteAll(db)
        }
    }

    func nextSortOrder(conversationId: String) async throws -> Int {
        try await read { db in
            let maxOrder = try Int.fetchOne(
                db,
                MessageRecord
                    .select(max(Column("sortOrder")))
                    .filter(Column("conversationId") == conversationId)
            )
            return (maxOrder ?? 0) + 1
        }
    }
}
