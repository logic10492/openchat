import Foundation
import GRDB

extension DatabaseManager {
    func fetchStage(conversationId: String) async throws -> StageRecord? {
        try await read { db in
            try StageRecord
                .filter(Column("conversationId") == conversationId)
                .fetchOne(db)
        }
    }

    func fetchStageContext(conversationId: String) async throws -> StageContext? {
        try await read { db in
            guard let stage = try StageRecord
                .filter(Column("conversationId") == conversationId)
                .fetchOne(db)
            else { return nil }

            let participants = try StageParticipantRecord
                .filter(Column("stageId") == stage.id)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
            let instructions = try StageInstructionRecord
                .filter(Column("stageId") == stage.id)
                .order(Column("createdAt").asc)
                .fetchAll(db)

            return StageContext(
                stage: stage,
                participants: participants,
                instructions: instructions
            )
        }
    }

    func saveStage(_ stage: StageRecord) async throws {
        try await write { db in
            try stage.save(db)
        }
    }

    func createStage(
        conversationId: String,
        title: String?,
        directorMode: DirectorMode = .silent
    ) async throws -> StageRecord {
        let now = Date()
        let stage = StageRecord(
            id: UUID().uuidString,
            conversationId: conversationId,
            title: title,
            directorMode: directorMode.rawValue,
            isEnabled: true,
            createdAt: now,
            updatedAt: now
        )
        try await saveStage(stage)
        return stage
    }

    func setStageDirectorMode(stageId: String, mode: DirectorMode) async throws {
        try await write { db in
            _ = try StageRecord
                .filter(Column("id") == stageId)
                .updateAll(
                    db,
                    Column("directorMode").set(to: mode.rawValue),
                    Column("updatedAt").set(to: Date())
                )
        }
    }

    func fetchStageParticipants(stageId: String) async throws -> [StageParticipantRecord] {
        try await read { db in
            try StageParticipantRecord
                .filter(Column("stageId") == stageId)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }

    func addStageParticipant(
        stageId: String,
        characterCard: CharacterCardRecord
    ) async throws -> StageParticipantRecord {
        try await write { db in
            if let existing = try StageParticipantRecord
                .filter(Column("stageId") == stageId && Column("characterCardId") == characterCard.id)
                .fetchOne(db) {
                return existing
            }

            let maxOrder = try Int.fetchOne(
                db,
                StageParticipantRecord
                    .select(max(Column("sortOrder")))
                    .filter(Column("stageId") == stageId)
            )
            let now = Date()
            let participant = StageParticipantRecord(
                id: UUID().uuidString,
                stageId: stageId,
                characterCardId: characterCard.id,
                displayName: characterCard.name,
                visibility: StageParticipantVisibility.present.rawValue,
                isActive: true,
                sortOrder: (maxOrder ?? 0) + 1,
                createdAt: now,
                updatedAt: now
            )
            try participant.insert(db)
            return participant
        }
    }

    func removeStageParticipant(id: String) async throws {
        try await write { db in
            _ = try StageParticipantRecord.deleteOne(db, key: id)
        }
    }

    func saveStageInstruction(_ instruction: StageInstructionRecord) async throws {
        try await write { db in
            try instruction.save(db)
        }
    }
}
