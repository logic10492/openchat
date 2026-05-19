import Foundation
import GRDB
import SqliteVec
import Testing

@testable import OpenChat

@Suite("Database migrations")
struct MigrationTests {
    @Test func test_migrations_do_not_reference_runtime_record_or_enum_symbols() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migrationsURL = projectRoot
            .appendingPathComponent("OpenChat")
            .appendingPathComponent("Core")
            .appendingPathComponent("Database")
            .appendingPathComponent("Migrations.swift")
        let source = try String(contentsOf: migrationsURL, encoding: .utf8)
        let forbiddenReferences = [
            ".databaseTableName",
            "APIMode.",
            "WorldBookEntryPosition.",
            "ContextStrategy.",
            "CompressionMode.",
            "EmbeddingService."
        ]
        let violations = forbiddenReferences.filter { source.contains($0) }

        #expect(
            violations.isEmpty,
            "Migrations must use migration-local historical constants, not runtime symbols: \(violations.joined(separator: ", "))"
        )
    }

    @Test func test_v1_creates_expected_tables_and_indexes() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }

        #expect(tableNames.contains("api_endpoint"))
        #expect(tableNames.contains("character_card"))
        #expect(tableNames.contains("world_book"))
        #expect(tableNames.contains("world_book_entry"))
        #expect(tableNames.contains("conversation"))
        #expect(tableNames.contains("message"))
    }

    @Test func test_v18_creates_stage_tables_and_message_speaker_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        let messageColumns = try await manager.read { db in
            try db.columns(in: "message").map(\.name)
        }

        #expect(tableNames.contains("stage"))
        #expect(tableNames.contains("stage_participant"))
        #expect(tableNames.contains("stage_instruction"))
        #expect(messageColumns.contains("stageId"))
        #expect(messageColumns.contains("speakerKind"))
        #expect(messageColumns.contains("speakerId"))
        #expect(messageColumns.contains("speakerName"))
    }

    @Test func test_v18_stage_cascade_removes_participants_and_instructions() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "stage-cascade-conversation")
        let card = TestHelpers.makeCharacterCard(id: "stage-cascade-card")
        try await manager.write { db in
            try card.insert(db)
            try conversation.insert(db)
        }
        let stage = try await manager.createStage(
            conversationId: conversation.id,
            title: "Stage",
            directorMode: .userControlled
        )
        _ = try await manager.addStageParticipant(stageId: stage.id, characterCard: card)
        try await manager.saveStageInstruction(
            StageInstructionRecord(
                id: "instruction-1",
                stageId: stage.id,
                source: StageInstructionSource.user.rawValue,
                content: "Hold the reveal.",
                visibility: StageInstructionVisibility.hiddenFromCharacters.rawValue,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )

        try await manager.deleteConversation(id: conversation.id)

        let participantCount = try await manager.read { db in
            try StageParticipantRecord.fetchCount(db)
        }
        let instructionCount = try await manager.read { db in
            try StageInstructionRecord.fetchCount(db)
        }
        #expect(participantCount == 0)
        #expect(instructionCount == 0)
    }

    @Test func test_foreign_key_cascade_removes_world_book_entries() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook()
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id)

        try await manager.write { db in
            try worldBook.insert(db)
            try entry.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM world_book WHERE id = ?", arguments: [worldBook.id])
        }

        let count = try await manager.read { db in
            try WorldBookEntryRecord.fetchCount(db)
        }

        #expect(count == 0)
    }

    @Test func test_v2_adds_worldBookId_to_character_card() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "character_card").map(\.name)
        }
        #expect(columns.contains("worldBookId"))
    }

    @Test func test_v2_character_card_worldBookId_set_null_on_world_book_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook()
        let now = Date()
        var card = CharacterCardRecord(
            id: UUID().uuidString,
            name: "Test",
            createdAt: now,
            updatedAt: now
        )
        card.worldBookId = worldBook.id
        let cardSnapshot = card

        try await manager.write { db in
            try worldBook.insert(db)
            try cardSnapshot.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM world_book WHERE id = ?", arguments: [worldBook.id])
        }

        let updated = try await manager.read { db in
            try CharacterCardRecord.fetchOne(db, key: cardSnapshot.id)
        }
        #expect(updated?.worldBookId == nil)
    }

    @Test func test_v3_removes_worldBookId_from_conversation() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(!columns.contains("worldBookId"))
    }

    @Test func test_v4_creates_memory_entry_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        #expect(tableNames.contains("memory_entry"))
    }

    @Test func test_v4_memory_entry_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "memory_entry").map(\.name)
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("characterCardId"))
        #expect(columns.contains("sourceConversationId"))
        #expect(columns.contains("content"))
        #expect(columns.contains("memoryType"))
        #expect(columns.contains("importance"))
        #expect(columns.contains("createdAt"))
        #expect(columns.contains("updatedAt"))
    }

    @Test func test_v4_memory_entry_cascade_on_character_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)

        try await manager.write { db in
            try card.insert(db)
            try memory.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM character_card WHERE id = ?", arguments: [card.id])
        }

        let count = try await manager.read { db in
            try MemoryEntryRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v8 endpoint_model decoupling

    @Test func test_v8_creates_endpoint_model_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        #expect(tableNames.contains("endpoint_model"))
    }

    @Test func test_v8_endpoint_model_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "endpoint_model").map(\.name)
        }
        #expect(columns.contains("id"))
        #expect(columns.contains("endpointId"))
        #expect(columns.contains("modelId"))
        #expect(columns.contains("maxContextTokens"))
        #expect(columns.contains("apiMode"))
        #expect(columns.contains("isDefault"))
        #expect(columns.contains("isManual"))
        #expect(columns.contains("createdAt"))
    }

    @Test func test_v8_conversation_has_modelName_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(columns.contains("modelName"))
    }

    @Test func test_v8_api_endpoint_no_longer_has_model_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "api_endpoint").map(\.name)
        }
        #expect(!columns.contains("modelName"))
        #expect(!columns.contains("maxContextTokens"))
        #expect(!columns.contains("apiMode"))
    }

    @Test func test_v8_endpoint_model_cascade_on_endpoint_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "ep1",
            name: "Test",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "m1",
            endpointId: "ep1",
            modelId: "gpt-4o",
            maxContextTokens: 4096,
            apiMode: "chatCompletions",
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: false,
            createdAt: now
        )

        try await manager.write { db in
            try endpoint.insert(db)
            try model.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM api_endpoint WHERE id = 'ep1'")
        }

        let count = try await manager.read { db in
            try EndpointModelRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v9

    @Test func test_v9_conversation_has_isTitleGenerated_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }
        #expect(columns.contains("isTitleGenerated"))
    }

    @Test func test_v9_isTitleGenerated_defaults_to_false() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation()
        try await manager.write { db in
            try conversation.insert(db)
        }

        let fetched = try await manager.read { db in
            try ConversationRecord.fetchOne(db, id: conversation.id)
        }

        #expect(fetched?.isTitleGenerated == false)
    }

    // MARK: - v10 provider dialect

    @Test func test_v10_endpoint_model_has_providerDialect_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "endpoint_model").map(\.name)
        }

        #expect(columns.contains("providerDialect"))
    }

    @Test func test_v10_providerDialect_defaults_to_openAICompatible() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "ep-provider-default",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        try await manager.saveEndpoint(endpoint)
        try await manager.ensureDefaultModel(endpointId: endpoint.id)

        let model = try await manager.fetchDefaultModel(endpointId: endpoint.id)
        #expect(model?.providerDialect == "openAICompatible")
    }

    @Test func test_v10_backfills_existing_deepseek_v4_models() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            if let connection = db.sqliteConnection {
                registerSqliteVec(connection)
            }
        }
        let dbQueue = try DatabaseQueue(configuration: configuration)
        var migrator = Migrations.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v9_add_is_title_generated")

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO api_endpoint (id, name, baseURL, apiKey, isDefault, createdAt, updatedAt)
                VALUES ('ep-deepseek', 'DeepSeek', 'https://api.deepseek.com', NULL, 1, ?, ?)
                """, arguments: [Date(), Date()])
            try db.execute(sql: """
                INSERT INTO endpoint_model (id, endpointId, modelId, maxContextTokens, apiMode, isDefault, isManual, createdAt)
                VALUES ('model-deepseek-pro', 'ep-deepseek', 'deepseek-v4-pro', 4096, 'chatCompletions', 1, 1, ?)
                """, arguments: [Date()])
        }

        try migrator.migrate(dbQueue)

        let row = try dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT providerDialect, maxContextTokens
                FROM endpoint_model
                WHERE id = 'model-deepseek-pro'
                """)
        }

        #expect(row?["providerDialect"] as String? == "deepSeekV4")
        #expect(row?["maxContextTokens"] as Int? == 1_000_000)
    }

    // MARK: - v11 compression checkpoints

    @Test func test_v11_creates_compression_checkpoint_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }

        #expect(tableNames.contains("conversation_compression_checkpoint"))
    }

    @Test func test_v11_compression_checkpoint_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation_compression_checkpoint").map(\.name)
        }

        #expect(columns.contains("id"))
        #expect(columns.contains("conversationId"))
        #expect(columns.contains("parentCheckpointId"))
        #expect(columns.contains("sourceStartSortOrder"))
        #expect(columns.contains("sourceEndSortOrder"))
        #expect(columns.contains("sourceHash"))
        #expect(columns.contains("summary"))
        #expect(columns.contains("summaryTokenCount"))
        #expect(columns.contains("endpointId"))
        #expect(columns.contains("modelName"))
        #expect(columns.contains("modelMaxContextTokens"))
        #expect(columns.contains("effectiveCompactWindowTokens"))
        #expect(columns.contains("autoCompactTokenLimit"))
        #expect(columns.contains("createdAt"))
    }

    @Test func test_v11_compression_checkpoint_cascade_on_conversation_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-checkpoint")
        let checkpoint = CompressionCheckpointRecord(
            id: "checkpoint-1",
            conversationId: conversation.id,
            parentCheckpointId: nil,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            sourceHash: "hash",
            summary: "summary",
            summaryTokenCount: 1,
            endpointId: nil,
            modelName: "gpt-4o-mini",
            modelMaxContextTokens: 4096,
            effectiveCompactWindowTokens: 4096,
            autoCompactTokenLimit: 1638,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try await manager.write { db in
            try conversation.insert(db)
            try checkpoint.insert(db)
            try ConversationRecord.deleteOne(db, key: conversation.id)
        }

        let count = try await manager.read { db in
            try CompressionCheckpointRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v12 compression mode

    @Test func test_v12_conversation_has_compressionMode_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }

        #expect(columns.contains("compressionMode"))
    }

    @Test func test_v12_compressionMode_defaults_to_standard() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()

        try await manager.write { db in
            try db.execute(sql: """
                INSERT INTO conversation (
                    id, title, contextStrategy, slowPlotMode, isTitleGenerated, isPinned, createdAt, updatedAt
                )
                VALUES ('conv-compression-mode-default', 'Mode Default', 'compression', 1, 0, 0, ?, ?)
                """, arguments: [now, now])
        }

        let compressionMode = try await manager.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT compressionMode FROM conversation WHERE id = ?",
                arguments: ["conv-compression-mode-default"]
            )?["compressionMode"] as String?
        }

        #expect(compressionMode == "standard")
    }

    // MARK: - v13 lastExtractedSortOrder

    @Test func test_v13_conversation_has_lastExtractedSortOrder_column() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "conversation").map(\.name)
        }

        #expect(columns.contains("lastExtractedSortOrder"))
    }

    @Test func test_v13_lastExtractedSortOrder_defaults_to_null() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()

        try await manager.write { db in
            try db.execute(sql: """
                INSERT INTO conversation (
                    id, title, contextStrategy, compressionMode, slowPlotMode, isTitleGenerated, isPinned, createdAt, updatedAt
                )
                VALUES ('conv-leso-default', 'LESO Default', 'truncation', 'standard', 1, 0, 0, ?, ?)
                """, arguments: [now, now])
        }

        let value = try await manager.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT lastExtractedSortOrder FROM conversation WHERE id = ?",
                arguments: ["conv-leso-default"]
            )?["lastExtractedSortOrder"] as Int?
        }

        #expect(value == nil)
    }

    // MARK: - v14 memory_entry_provenance

    @Test func test_v14_creates_memory_entry_provenance_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        #expect(tableNames.contains("memory_entry_provenance"))
    }

    @Test func test_v14_memory_entry_provenance_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "memory_entry_provenance").map(\.name)
        }
        #expect(columns.contains("memoryEntryId"))
        #expect(columns.contains("sourceStartSortOrder"))
        #expect(columns.contains("sourceEndSortOrder"))
        #expect(columns.contains("sourceMessageIds"))
        #expect(columns.contains("extractionModel"))
        #expect(columns.contains("extractionPromptVersion"))
        #expect(columns.contains("confidence"))
        #expect(columns.contains("dedupeKey"))
        #expect(columns.contains("tags"))
        #expect(columns.contains("createdAt"))
        #expect(columns.contains("updatedAt"))
    }

    @Test func test_v14_memory_entry_provenance_cascade_on_memory_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id)
        let provenance = MemoryEntryProvenanceRecord(
            memoryEntryId: memory.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            extractionPromptVersion: "v2",
            createdAt: Date(),
            updatedAt: Date()
        )

        try await manager.write { db in
            try card.insert(db)
            try memory.insert(db)
            try provenance.insert(db)
        }

        try await manager.write { db in
            try db.execute(sql: "DELETE FROM memory_entry WHERE id = ?", arguments: [memory.id])
        }

        let count = try await manager.read { db in
            try MemoryEntryProvenanceRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v15 world_book_entry_embedding

    @Test func test_v15_creates_world_book_entry_embedding_table() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }

        #expect(tableNames.contains("world_book_entry_embedding"))
    }

    @Test func test_v15_world_book_entry_embedding_accepts_384_dimension_vectors() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let embedding = Array(repeating: Float(0), count: 384)
        let blob = embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        try await manager.write { db in
            try db.execute(
                sql: "INSERT INTO world_book_entry_embedding(entry_id, embedding) VALUES (?, ?)",
                arguments: ["entry-vector-dimension", blob]
            )
        }

        let count = try await manager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM world_book_entry_embedding WHERE entry_id = ?",
                arguments: ["entry-vector-dimension"]
            ) ?? 0
        }
        #expect(count == 1)
    }

    // MARK: - v16 world_book_entry_embedding_meta

    @Test func test_v16_creates_world_book_embedding_meta_columns() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let columns = try await manager.read { db in
            try db.columns(in: "world_book_entry_embedding_meta").map(\.name)
        }

        #expect(columns.contains("entryId"))
        #expect(columns.contains("contentHash"))
        #expect(columns.contains("embeddingModel"))
        #expect(columns.contains("embeddingDimension"))
        #expect(columns.contains("status"))
        #expect(columns.contains("embeddedAt"))
        #expect(columns.contains("lastAttemptAt"))
        #expect(columns.contains("lastError"))
        #expect(columns.contains("updatedAt"))
    }

    @Test func test_v16_world_book_embedding_meta_has_status_and_model_indexes() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let indexNames = try await manager.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
                arguments: ["world_book_entry_embedding_meta"]
            ).compactMap { $0["name"] as String? }
        }

        #expect(indexNames.contains("idx_world_book_entry_embedding_meta_status"))
        #expect(indexNames.contains("idx_world_book_entry_embedding_meta_model"))
    }

    @Test func test_v16_world_book_embedding_meta_cascade_on_entry_delete() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook()
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id)
        let meta = WorldBookEntryEmbeddingMetaRecord(
            entryId: entry.id,
            contentHash: "hash-a",
            embeddingModel: "MultilingualE5Small",
            embeddingDimension: 384,
            status: WorldBookEmbeddingStatus.indexed.rawValue,
            embeddedAt: Date(),
            lastAttemptAt: Date(),
            lastError: nil,
            updatedAt: Date()
        )

        try await manager.write { db in
            try worldBook.insert(db)
            try entry.insert(db)
            try meta.insert(db)
            try db.execute(sql: "DELETE FROM world_book_entry WHERE id = ?", arguments: [entry.id])
        }

        let count = try await manager.read { db in
            try WorldBookEntryEmbeddingMetaRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    // MARK: - v17 memory_entry_link

    @Test func test_v17_creates_memory_entry_link_table_columns_and_indexes() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let tableNames = try await manager.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .compactMap { $0["name"] as String? }
        }
        let columns = try await manager.read { db in
            try db.columns(in: "memory_entry_link").map(\.name)
        }
        let indexNames = try await manager.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
                arguments: ["memory_entry_link"]
            ).compactMap { $0["name"] as String? }
        }

        #expect(tableNames.contains("memory_entry_link"))
        #expect(columns.contains("id"))
        #expect(columns.contains("fromMemoryEntryId"))
        #expect(columns.contains("toMemoryEntryId"))
        #expect(columns.contains("relation"))
        #expect(columns.contains("createdAt"))
        #expect(indexNames.contains("idx_memory_entry_link_fromMemoryEntryId"))
        #expect(indexNames.contains("idx_memory_entry_link_toMemoryEntryId"))
        #expect(indexNames.contains("idx_memory_entry_link_relation"))
    }

    @Test func test_v17_memory_entry_link_cascades_when_from_memory_deleted() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation", characterCardId: card.id)
        let link = MemoryEntryLinkRecord(
            id: "link-from-cascade",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .summarizes,
            createdAt: Date()
        )

        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try observation.insert(db)
            try link.insert(db)
            try db.execute(sql: "DELETE FROM memory_entry WHERE id = ?", arguments: [observation.id])
        }

        let count = try await manager.read { db in
            try MemoryEntryLinkRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test func test_v17_memory_entry_link_cascades_when_to_memory_deleted() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard()
        let source = TestHelpers.makeMemoryEntry(id: "memory-link-source-target-cascade", characterCardId: card.id)
        let observation = TestHelpers.makeMemoryEntry(id: "memory-link-observation-target-cascade", characterCardId: card.id)
        let link = MemoryEntryLinkRecord(
            id: "link-to-cascade",
            fromMemoryEntryId: observation.id,
            toMemoryEntryId: source.id,
            relation: .summarizes,
            createdAt: Date()
        )

        try await manager.write { db in
            try card.insert(db)
            try source.insert(db)
            try observation.insert(db)
            try link.insert(db)
            try db.execute(sql: "DELETE FROM memory_entry WHERE id = ?", arguments: [source.id])
        }

        let count = try await manager.read { db in
            try MemoryEntryLinkRecord.fetchCount(db)
        }
        #expect(count == 0)
    }
}
