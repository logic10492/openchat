import Foundation
import GRDB

struct VectorStore: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingDimension = EmbeddingService.embeddingDimension

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func insert(entryId: String, embedding: [Float]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try insertEmbedding(entryId: entryId, blob: blob, in: db)
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try entry.save(db)
                try insertEmbedding(entryId: entry.id, blob: blob, in: db)
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func insert(entry: MemoryEntryRecord, embedding: [Float], links: [MemoryEntryLinkRecord]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        let normalizedLinks = try validateLinksForAtomicInsert(links, fromMemoryEntryId: entry.id)
        do {
            try await databaseManager.write { db in
                try entry.save(db)
                try insertEmbedding(entryId: entry.id, blob: blob, in: db)
                for link in normalizedLinks {
                    try link.save(db)
                }
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {
        do {
            let items = try entries.map { item in
                try validateDimension(item.embedding)
                return (entry: item.entry, blob: embeddingToBlob(item.embedding))
            }

            try await databaseManager.write { db in
                for item in items {
                    try item.entry.save(db)
                    try insertEmbedding(entryId: item.entry.id, blob: item.blob, in: db)
                }
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func insert(
        entries: [(entry: MemoryEntryRecord, embedding: [Float])],
        provenances: [String: MemoryEntryProvenanceRecord]
    ) async throws {
        do {
            let items = try entries.map { item in
                try validateDimension(item.embedding)
                return (entry: item.entry, blob: embeddingToBlob(item.embedding))
            }

            try await databaseManager.write { db in
                for item in items {
                    try item.entry.save(db)
                    try insertEmbedding(entryId: item.entry.id, blob: item.blob, in: db)
                    if let provenance = provenances[item.entry.id] {
                        try provenance.save(db)
                    }
                }
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int = 5
    ) async throws -> [(entryId: String, distance: Float)] {
        try validateDimension(query)
        let blob = embeddingToBlob(query)
        do {
            return try await databaseManager.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT me.entry_id, me.distance
                    FROM memory_embedding me
                    WHERE me.entry_id IN (
                        SELECT id FROM memory_entry WHERE characterCardId = ?
                    )
                    AND me.embedding MATCH ?
                    AND me.k = ?
                    ORDER BY me.distance
                    """, arguments: [characterCardId, blob, limit])
                return rows.map { row in
                    (entryId: row["entry_id"] as String, distance: row["distance"] as Float)
                }
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func delete(entryId: String) async throws {
        do {
            try await databaseManager.write { db in
                try db.execute(
                    sql: "DELETE FROM memory_embedding WHERE entry_id = ?",
                    arguments: [entryId]
                )
                _ = try MemoryEntryRecord.deleteOne(db, key: entryId)
            }
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func deleteAll(characterCardId: String) async throws {
        do {
            try await databaseManager.write { db in
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
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    private func validateDimension(_ embedding: [Float]) throws {
        guard embedding.count == embeddingDimension else {
            throw MemoryError.vectorStoreError(
                underlying: VectorStoreValidationError.invalidDimension(
                    expected: embeddingDimension,
                    actual: embedding.count
                )
            )
        }
    }

    private func validateLinksForAtomicInsert(
        _ links: [MemoryEntryLinkRecord],
        fromMemoryEntryId: String
    ) throws -> [MemoryEntryLinkRecord] {
        let supportedRelations = Set(MemoryEntryLinkRelation.allCases.map(\.rawValue))
        var seen = Set<VectorStoreLinkKey>()
        var normalizedLinks: [MemoryEntryLinkRecord] = []

        for link in links {
            var normalizedLink = link
            normalizedLink.fromMemoryEntryId = link.fromMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedLink.toMemoryEntryId = link.toMemoryEntryId.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedLink.relation = link.relation.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedLink.fromMemoryEntryId.isEmpty else {
                throw MemoryError.vectorStoreError(underlying: MemoryEntryLinkValidationError.emptyFromMemoryEntryId)
            }
            guard !normalizedLink.toMemoryEntryId.isEmpty else {
                throw MemoryError.vectorStoreError(underlying: MemoryEntryLinkValidationError.emptyToMemoryEntryId)
            }
            guard normalizedLink.fromMemoryEntryId == fromMemoryEntryId else {
                throw MemoryError.vectorStoreError(
                    underlying: VectorStoreLinkValidationError.unexpectedFromMemoryEntryId(
                        expected: fromMemoryEntryId,
                        actual: normalizedLink.fromMemoryEntryId
                    )
                )
            }
            guard normalizedLink.fromMemoryEntryId != normalizedLink.toMemoryEntryId else {
                throw MemoryError.vectorStoreError(
                    underlying: MemoryEntryLinkValidationError.selfLink(
                        memoryEntryId: normalizedLink.fromMemoryEntryId
                    )
                )
            }
            guard supportedRelations.contains(normalizedLink.relation) else {
                throw MemoryError.vectorStoreError(
                    underlying: MemoryEntryLinkValidationError.invalidRelation(normalizedLink.relation)
                )
            }

            let key = VectorStoreLinkKey(
                fromMemoryEntryId: normalizedLink.fromMemoryEntryId,
                toMemoryEntryId: normalizedLink.toMemoryEntryId,
                relation: normalizedLink.relation
            )
            guard seen.insert(key).inserted else {
                throw MemoryError.vectorStoreError(
                    underlying: VectorStoreLinkValidationError.duplicateLink(
                        fromMemoryEntryId: key.fromMemoryEntryId,
                        toMemoryEntryId: key.toMemoryEntryId,
                        relation: key.relation
                    )
                )
            }
            normalizedLinks.append(normalizedLink)
        }

        return normalizedLinks
    }

    private func insertEmbedding(entryId: String, blob: Data, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO memory_embedding(entry_id, embedding) VALUES (?, ?)",
            arguments: [entryId, blob]
        )
    }

    private func embeddingToBlob(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

private enum VectorStoreValidationError: LocalizedError, Sendable {
    case invalidDimension(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidDimension(let expected, let actual):
            "Invalid embedding dimension: expected \(expected), got \(actual)"
        }
    }
}

private enum VectorStoreLinkValidationError: LocalizedError, Sendable {
    case unexpectedFromMemoryEntryId(expected: String, actual: String)
    case duplicateLink(fromMemoryEntryId: String, toMemoryEntryId: String, relation: String)

    var errorDescription: String? {
        switch self {
        case let .unexpectedFromMemoryEntryId(expected, actual):
            "Memory entry link source id \(actual) does not match inserted memory id \(expected)."
        case let .duplicateLink(fromMemoryEntryId, toMemoryEntryId, relation):
            "Memory entry link already exists: \(fromMemoryEntryId) -> \(toMemoryEntryId) (\(relation))."
        }
    }
}

private struct VectorStoreLinkKey: Hashable {
    var fromMemoryEntryId: String
    var toMemoryEntryId: String
    var relation: String
}
