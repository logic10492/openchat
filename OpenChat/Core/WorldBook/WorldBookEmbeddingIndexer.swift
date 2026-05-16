import Foundation
import GRDB

struct WorldBookEmbeddingIndexer: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingProvider: any EmbeddingProvider
    private let vectorStore: WorldBookVectorStore
    private let embeddingModelId: String
    private let embeddingDimension: Int
    private let now: @Sendable () -> Date

    init(
        databaseManager: DatabaseManager,
        embeddingProvider: any EmbeddingProvider,
        vectorStore: WorldBookVectorStore,
        embeddingModelId: String = EmbeddingService.embeddingModelId,
        embeddingDimension: Int = EmbeddingService.embeddingDimension,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.databaseManager = databaseManager
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.embeddingModelId = embeddingModelId
        self.embeddingDimension = embeddingDimension
        self.now = now
    }

    func index(entry: WorldBookEntryRecord) async throws -> WorldBookIndexingResult {
        var computedContentHash: String?
        do {
            let embeddingText = try WorldBookEmbeddingTextBuilder.text(for: entry)
            let contentHash = WorldBookEntryHasher.hash(
                embeddingText: embeddingText,
                modelId: embeddingModelId,
                dimension: embeddingDimension
            )
            computedContentHash = contentHash

            if try await isFresh(entryId: entry.id, contentHash: contentHash) {
                return WorldBookIndexingResult(
                    entryId: entry.id,
                    outcome: .skippedFresh,
                    contentHash: contentHash
                )
            }

            let embedding = try embeddingProvider.embed(embeddingText, isQuery: false)
            let timestamp = now()
            let meta = WorldBookEntryEmbeddingMetaRecord(
                entryId: entry.id,
                contentHash: contentHash,
                embeddingModel: embeddingModelId,
                embeddingDimension: embeddingDimension,
                status: WorldBookEmbeddingStatus.indexed.rawValue,
                embeddedAt: timestamp,
                lastAttemptAt: timestamp,
                lastError: nil,
                updatedAt: timestamp
            )
            try await vectorStore.upsert(entryId: entry.id, embedding: embedding, meta: meta)

            return WorldBookIndexingResult(
                entryId: entry.id,
                outcome: .indexed,
                contentHash: contentHash
            )
        } catch let error as WorldBookError {
            try await recordFailedMeta(entryId: entry.id, contentHash: computedContentHash, error: error)
            throw error
        } catch {
            let wrapped = WorldBookError.embeddingFailed(entryId: entry.id, underlying: error)
            try await recordFailedMeta(entryId: entry.id, contentHash: computedContentHash, error: wrapped)
            throw wrapped
        }
    }

    func index(entries: [WorldBookEntryRecord]) async throws -> WorldBookIndexingBatchResult {
        var indexedCount = 0
        var skippedFreshCount = 0
        var failed: [WorldBookIndexingFailure] = []

        for entry in entries {
            do {
                let result = try await index(entry: entry)
                switch result.outcome {
                case .indexed:
                    indexedCount += 1
                case .skippedFresh:
                    skippedFreshCount += 1
                }
            } catch {
                failed.append(
                    WorldBookIndexingFailure(
                        entryId: entry.id,
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        return WorldBookIndexingBatchResult(
            indexedCount: indexedCount,
            skippedFreshCount: skippedFreshCount,
            failed: failed
        )
    }

    func rebuildMissingOrStale(worldBookId: String, limit: Int? = nil) async throws -> WorldBookIndexingBatchResult {
        let entries = try await fetchEntries(worldBookId: worldBookId)
        return try await rebuild(entries: entries, limit: limit)
    }

    func rebuildAllMissingOrStale(limit: Int? = nil) async throws -> WorldBookIndexingBatchResult {
        let entries = try await fetchEntries(worldBookId: nil)
        return try await rebuild(entries: entries, limit: limit)
    }

    func markNeedsRebuild(entryId: String, reason: WorldBookIndexRebuildReason) async throws {
        let timestamp = now()
        do {
            try await databaseManager.write { db in
                if var meta = try WorldBookEntryEmbeddingMetaRecord.fetchOne(db, key: entryId) {
                    meta.status = WorldBookEmbeddingStatus.needsRebuild.rawValue
                    meta.lastError = reason.rawValue
                    meta.updatedAt = timestamp
                    try meta.save(db)
                } else {
                    let meta = WorldBookEntryEmbeddingMetaRecord(
                        entryId: entryId,
                        contentHash: "",
                        embeddingModel: embeddingModelId,
                        embeddingDimension: embeddingDimension,
                        status: WorldBookEmbeddingStatus.needsRebuild.rawValue,
                        embeddedAt: nil,
                        lastAttemptAt: nil,
                        lastError: reason.rawValue,
                        updatedAt: timestamp
                    )
                    try meta.insert(db)
                }
            }
        } catch {
            throw WorldBookError.indexerError(underlying: error)
        }
    }

    private func isFresh(entryId: String, contentHash: String) async throws -> Bool {
        do {
            return try await databaseManager.read { db in
                guard let meta = try WorldBookEntryEmbeddingMetaRecord.fetchOne(db, key: entryId) else {
                    return false
                }
                return meta.statusValue == .indexed &&
                    meta.contentHash == contentHash &&
                    meta.embeddingModel == embeddingModelId &&
                    meta.embeddingDimension == embeddingDimension
            }
        } catch {
            throw WorldBookError.indexerError(underlying: error)
        }
    }

    private func rebuild(entries: [WorldBookEntryRecord], limit: Int?) async throws -> WorldBookIndexingBatchResult {
        let normalizedLimit = limit.map { max($0, 0) }
        var indexedCount = 0
        var skippedFreshCount = 0
        var failed: [WorldBookIndexingFailure] = []
        var attemptedRebuildCount = 0

        for entry in entries {
            if let normalizedLimit, attemptedRebuildCount >= normalizedLimit {
                break
            }

            do {
                let result = try await index(entry: entry)
                switch result.outcome {
                case .indexed:
                    indexedCount += 1
                    attemptedRebuildCount += 1
                case .skippedFresh:
                    skippedFreshCount += 1
                }
            } catch {
                failed.append(
                    WorldBookIndexingFailure(
                        entryId: entry.id,
                        errorDescription: error.localizedDescription
                    )
                )
                attemptedRebuildCount += 1
            }
        }

        return WorldBookIndexingBatchResult(
            indexedCount: indexedCount,
            skippedFreshCount: skippedFreshCount,
            failed: failed
        )
    }

    private func fetchEntries(worldBookId: String?) async throws -> [WorldBookEntryRecord] {
        do {
            return try await databaseManager.read { db in
                var request = WorldBookEntryRecord
                    .order(Column("updatedAt").asc, Column("id").asc)
                if let worldBookId {
                    request = request.filter(Column("worldBookId") == worldBookId)
                }
                return try request.fetchAll(db)
            }
        } catch {
            throw WorldBookError.indexerError(underlying: error)
        }
    }

    private func recordFailedMeta(entryId: String, contentHash: String?, error: Error) async throws {
        let timestamp = now()
        do {
            try await databaseManager.write { db in
                let existing = try WorldBookEntryEmbeddingMetaRecord.fetchOne(db, key: entryId)
                let meta = WorldBookEntryEmbeddingMetaRecord(
                    entryId: entryId,
                    contentHash: contentHash ?? existing?.contentHash ?? "",
                    embeddingModel: embeddingModelId,
                    embeddingDimension: embeddingDimension,
                    status: WorldBookEmbeddingStatus.failed.rawValue,
                    embeddedAt: existing?.embeddedAt,
                    lastAttemptAt: timestamp,
                    lastError: error.localizedDescription,
                    updatedAt: timestamp
                )
                try meta.save(db)
            }
        } catch {
            throw WorldBookError.indexerError(underlying: error)
        }
    }
}

struct WorldBookIndexingResult: Sendable {
    let entryId: String
    let outcome: WorldBookIndexingOutcome
    let contentHash: String
}

enum WorldBookIndexingOutcome: Sendable {
    case indexed
    case skippedFresh
}

struct WorldBookIndexingBatchResult: Sendable {
    let indexedCount: Int
    let skippedFreshCount: Int
    let failed: [WorldBookIndexingFailure]
}

struct WorldBookIndexingFailure: Sendable {
    let entryId: String
    let errorDescription: String
}

enum WorldBookIndexRebuildReason: String, Sendable {
    case contentChanged = "content_changed"
    case embeddingModelChanged = "embedding_model_changed"
    case manualRebuild = "manual_rebuild"
    case importCompleted = "import_completed"
}
