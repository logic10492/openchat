import Foundation
import GRDB

extension DatabaseManager {
    func fetchMemories(characterCardId: String) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchMemories(characterCardId: String, type: MemoryType) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .filter(Column("memoryType") == type.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchRecentMemories(
        characterCardId: String,
        limit: Int
    ) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchRecentHighValueMemories(
        characterCardId: String,
        limit: Int
    ) async throws -> [MemoryEntryRecord] {
        guard limit > 0 else { return [] }
        return try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .filter(
                    [MemoryType.relationship.rawValue, MemoryType.summary.rawValue].contains(Column("memoryType")) ||
                        Column("importance") >= 70
                )
                .order(
                    sql: """
                    CASE
                      WHEN memoryType = ? THEN 0
                      WHEN memoryType = ? THEN 1
                      ELSE 2
                    END,
                    importance DESC,
                    createdAt DESC
                    """,
                    arguments: [MemoryType.relationship.rawValue, MemoryType.summary.rawValue]
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchMemoryCount(characterCardId: String) async throws -> Int {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .fetchCount(db)
        }
    }

    func hasMemoriesForConversation(conversationId: String) async throws -> Bool {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("sourceConversationId") == conversationId)
                .fetchCount(db) > 0
        }
    }

    func latestMemoryDate(conversationId: String) async throws -> Date? {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("sourceConversationId") == conversationId)
                .select(max(Column("createdAt")))
                .asRequest(of: Date?.self)
                .fetchOne(db) ?? nil
        }
    }

    func saveMemory(_ memory: MemoryEntryRecord) async throws {
        try await write { db in
            try memory.save(db)
        }
    }

    func deleteMemory(id: String) async throws {
        try await write { db in
            try db.execute(
                sql: "DELETE FROM memory_embedding WHERE entry_id = ?",
                arguments: [id]
            )
            _ = try MemoryEntryRecord.deleteOne(db, key: id)
        }
    }

    func deleteAllMemories(characterCardId: String) async throws {
        try await write { db in
            try db.execute(sql: """
                DELETE FROM memory_embedding
                WHERE entry_id IN (
                    SELECT id FROM memory_entry WHERE characterCardId = ?
                )
                """, arguments: [characterCardId])
            _ = try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .deleteAll(db)
        }
    }

    func fetchMemories(ids: [String]) async throws -> [MemoryEntryRecord] {
        guard !ids.isEmpty else { return [] }
        return try await read { db in
            try MemoryEntryRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }

    // MARK: - Memory Provenance

    func saveMemoryProvenance(_ provenance: MemoryEntryProvenanceRecord) async throws {
        try await write { db in
            try provenance.save(db)
        }
    }

    func fetchMemoryProvenance(memoryEntryId: String) async throws -> MemoryEntryProvenanceRecord? {
        try await read { db in
            try MemoryEntryProvenanceRecord.fetchOne(db, key: memoryEntryId)
        }
    }

    func fetchMemoryProvenances(memoryEntryIds: [String]) async throws -> [MemoryEntryProvenanceRecord] {
        guard !memoryEntryIds.isEmpty else { return [] }
        return try await read { db in
            try MemoryEntryProvenanceRecord
                .filter(memoryEntryIds.contains(Column("memoryEntryId")))
                .fetchAll(db)
        }
    }

    func deleteMemoryProvenance(memoryEntryId: String) async throws {
        try await write { db in
            _ = try MemoryEntryProvenanceRecord.deleteOne(db, key: memoryEntryId)
        }
    }

    // MARK: - Memory Entry Links

    func saveMemoryEntryLinks(_ links: [MemoryEntryLinkRecord]) async throws {
        let validatedLinks = try Self.validatedMemoryEntryLinks(links)
        guard !validatedLinks.isEmpty else { return }

        try await write { db in
            let fromMemoryEntryIds = validatedLinks.map(\.fromMemoryEntryId)
            var persistedKeys = try Set(
                MemoryEntryLinkRecord
                    .filter(fromMemoryEntryIds.contains(Column("fromMemoryEntryId")))
                    .fetchAll(db)
                    .map(MemoryEntryLinkDeduplicationKey.init)
            )
            for link in validatedLinks {
                let key = MemoryEntryLinkDeduplicationKey(link)
                if persistedKeys.insert(key).inserted {
                    try link.save(db)
                }
            }
        }
    }

    func fetchMemoryEntryLinks(fromMemoryEntryId: String) async throws -> [MemoryEntryLinkRecord] {
        let normalizedId = fromMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedId.isEmpty else { return [] }

        return try await read { db in
            try MemoryEntryLinkRecord
                .filter(Column("fromMemoryEntryId") == normalizedId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func fetchMemoryEntryLinks(toMemoryEntryId: String) async throws -> [MemoryEntryLinkRecord] {
        let normalizedId = toMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedId.isEmpty else { return [] }

        return try await read { db in
            try MemoryEntryLinkRecord
                .filter(Column("toMemoryEntryId") == normalizedId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    func fetchMemoryEntryLinks(memoryEntryIds: [String]) async throws -> [MemoryEntryLinkRecord] {
        let normalizedIds = memoryEntryIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedIds.isEmpty else { return [] }

        return try await read { db in
            try MemoryEntryLinkRecord
                .filter(normalizedIds.contains(Column("fromMemoryEntryId")) || normalizedIds.contains(Column("toMemoryEntryId")))
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    private static func validatedMemoryEntryLinks(_ links: [MemoryEntryLinkRecord]) throws -> [MemoryEntryLinkRecord] {
        let supportedRelations = Set(MemoryEntryLinkRelation.allCases.map(\.rawValue))
        var seen = Set<MemoryEntryLinkDeduplicationKey>()
        var validatedLinks: [MemoryEntryLinkRecord] = []

        for link in links {
            var normalizedLink = link
            normalizedLink.fromMemoryEntryId = link.fromMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedLink.toMemoryEntryId = link.toMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedLink.relation = link.relation.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedLink.fromMemoryEntryId.isEmpty else {
                throw MemoryEntryLinkValidationError.emptyFromMemoryEntryId
            }
            guard !normalizedLink.toMemoryEntryId.isEmpty else {
                throw MemoryEntryLinkValidationError.emptyToMemoryEntryId
            }
            guard normalizedLink.fromMemoryEntryId != normalizedLink.toMemoryEntryId else {
                throw MemoryEntryLinkValidationError.selfLink(memoryEntryId: normalizedLink.fromMemoryEntryId)
            }
            guard supportedRelations.contains(normalizedLink.relation) else {
                throw MemoryEntryLinkValidationError.invalidRelation(normalizedLink.relation)
            }

            let key = MemoryEntryLinkDeduplicationKey(
                fromMemoryEntryId: normalizedLink.fromMemoryEntryId,
                toMemoryEntryId: normalizedLink.toMemoryEntryId,
                relation: normalizedLink.relation
            )
            if seen.insert(key).inserted {
                validatedLinks.append(normalizedLink)
            }
        }

        return validatedLinks
    }
}

enum MemoryEntryLinkValidationError: LocalizedError, Equatable, Sendable {
    case emptyFromMemoryEntryId
    case emptyToMemoryEntryId
    case selfLink(memoryEntryId: String)
    case invalidRelation(String)

    var errorDescription: String? {
        switch self {
        case .emptyFromMemoryEntryId:
            "Memory entry link must include a source memory entry id."
        case .emptyToMemoryEntryId:
            "Memory entry link must include a target memory entry id."
        case let .selfLink(memoryEntryId):
            "Memory entry link cannot reference the same memory entry twice: \(memoryEntryId)."
        case let .invalidRelation(relation):
            "Memory entry link relation is unsupported: \(relation)."
        }
    }
}

private struct MemoryEntryLinkDeduplicationKey: Hashable {
    var fromMemoryEntryId: String
    var toMemoryEntryId: String
    var relation: String

    init(
        fromMemoryEntryId: String,
        toMemoryEntryId: String,
        relation: String
    ) {
        self.fromMemoryEntryId = fromMemoryEntryId
        self.toMemoryEntryId = toMemoryEntryId
        self.relation = relation
    }

    init(_ link: MemoryEntryLinkRecord) {
        self.fromMemoryEntryId = link.fromMemoryEntryId
        self.toMemoryEntryId = link.toMemoryEntryId
        self.relation = link.relation
    }
}
