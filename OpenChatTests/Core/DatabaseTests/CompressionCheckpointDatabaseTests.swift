import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("Compression checkpoint database")
struct CompressionCheckpointDatabaseTests {
    @Test func test_fetchLatestCompressionCheckpoint_returnsHighestSourceEnd() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-db")
        let older = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            id: "older",
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 4
        )
        let newer = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            id: "newer",
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 8
        )

        try await db.write { database in
            try conversation.insert(database)
            try older.insert(database)
            try newer.insert(database)
        }

        let fetched = try await db.fetchLatestCompressionCheckpoint(conversationId: conversation.id)
        #expect(fetched?.id == "newer")
    }

    @Test func test_deleteCompressionCheckpoints_afterSortOrder_removesAffectedRanges() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-delete")
        let keep = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            id: "keep",
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 3
        )
        let delete = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            id: "delete",
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 6
        )

        try await db.write { database in
            try conversation.insert(database)
            try keep.insert(database)
            try delete.insert(database)
        }

        try await db.deleteCompressionCheckpoints(conversationId: conversation.id, sourceEndAtOrAfter: 4)

        let remaining = try await db.fetchCompressionCheckpoints(conversationId: conversation.id)
        #expect(remaining.map(\.id) == ["keep"])
    }
}
