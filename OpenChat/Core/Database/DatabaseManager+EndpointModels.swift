import Foundation
import GRDB

extension DatabaseManager {
    func fetchEndpointModels(endpointId: String) async throws -> [EndpointModelRecord] {
        try await read { db in
            try EndpointModelRecord
                .filter(Column("endpointId") == endpointId)
                .order(Column("isDefault").desc, Column("modelId").asc)
                .fetchAll(db)
        }
    }

    func fetchDefaultModel(endpointId: String) async throws -> EndpointModelRecord? {
        try await read { db in
            try EndpointModelRecord
                .filter(Column("endpointId") == endpointId && Column("isDefault") == true)
                .fetchOne(db)
            ?? EndpointModelRecord
                .filter(Column("endpointId") == endpointId)
                .order(Column("createdAt").asc)
                .fetchOne(db)
        }
    }

    func fetchEndpointModel(endpointId: String, modelId: String) async throws -> EndpointModelRecord? {
        try await read { db in
            try EndpointModelRecord
                .filter(Column("endpointId") == endpointId && Column("modelId") == modelId)
                .fetchOne(db)
        }
    }

    func saveEndpointModel(_ model: EndpointModelRecord) async throws {
        try await write { db in
            if model.isDefault {
                try EndpointModelRecord
                    .filter(Column("endpointId") == model.endpointId && Column("id") != model.id)
                    .updateAll(db, Column("isDefault").set(to: false))
            }
            try model.save(db)
        }
    }

    func deleteEndpointModel(id: String) async throws {
        try await write { db in
            _ = try EndpointModelRecord.deleteOne(db, key: id)
        }
    }

    func setDefaultEndpointModel(id: String, endpointId: String) async throws {
        try await write { db in
            try EndpointModelRecord
                .filter(Column("endpointId") == endpointId)
                .updateAll(db, Column("isDefault").set(to: false))
            try EndpointModelRecord
                .filter(Column("id") == id)
                .updateAll(db, Column("isDefault").set(to: true))
        }
    }

    /// Merge fetched models from API into the database, preserving manual entries.
    func upsertFetchedModels(endpointId: String, models: [ModelObject]) async throws {
        try await write { db in
            let existing = try EndpointModelRecord
                .filter(Column("endpointId") == endpointId)
                .fetchAll(db)
            let existingIds = Set(existing.map(\.modelId))
            let fetchedIds = Set(models.map(\.id))

            // Remove non-manual entries that are no longer in fetched list
            for record in existing where !record.isManual && !fetchedIds.contains(record.modelId) {
                _ = try EndpointModelRecord.deleteOne(db, key: record.id)
            }

            let hasDefault = existing.contains(where: { $0.isDefault && (fetchedIds.contains($0.modelId) || $0.isManual) })
            var isFirst = !hasDefault

            // Insert new models from API
            for model in models where !existingIds.contains(model.id) {
                let record = EndpointModelRecord(
                    id: UUID().uuidString,
                    endpointId: endpointId,
                    modelId: model.id,
                    maxContextTokens: model.contextLength ?? 4096,
                    apiMode: APIMode.chatCompletions.rawValue,
                    isDefault: isFirst,
                    isManual: false,
                    createdAt: Date()
                )
                try record.insert(db)
                if isFirst { isFirst = false }
            }

            // Update context length for existing fetched models
            for model in models {
                if let contextLength = model.contextLength,
                   var existing = try EndpointModelRecord
                    .filter(Column("endpointId") == endpointId && Column("modelId") == model.id)
                    .fetchOne(db),
                   !existing.isManual {
                    existing.maxContextTokens = contextLength
                    try existing.update(db)
                }
            }
        }
    }

    /// Ensure the endpoint has at least one model; if empty, insert a "default" placeholder.
    func ensureDefaultModel(endpointId: String) async throws {
        try await write { db in
            let count = try EndpointModelRecord
                .filter(Column("endpointId") == endpointId)
                .fetchCount(db)
            if count == 0 {
                let record = EndpointModelRecord(
                    id: UUID().uuidString,
                    endpointId: endpointId,
                    modelId: "default",
                    maxContextTokens: AppConstants.defaultMaxContextTokens,
                    apiMode: APIMode.chatCompletions.rawValue,
                    isDefault: true,
                    isManual: true,
                    createdAt: Date()
                )
                try record.insert(db)
            }
        }
    }
}
