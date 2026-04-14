import Foundation
import GRDB

extension DatabaseManager {
    func fetchEndpoints() async throws -> [APIEndpointRecord] {
        try await read { db in
            try APIEndpointRecord
                .order(Column("isDefault").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchDefaultEndpoint() async throws -> APIEndpointRecord? {
        try await read { db in
            try APIEndpointRecord
                .filter(Column("isDefault") == true)
                .fetchOne(db)
        }
    }

    func fetchEndpoint(id: String?) async throws -> APIEndpointRecord? {
        guard let id else { return nil }
        return try await read { db in
            try APIEndpointRecord.fetchOne(db, key: id)
        }
    }

    func saveEndpoint(_ endpoint: APIEndpointRecord) async throws {
        try await write { db in
            if endpoint.isDefault {
                try APIEndpointRecord
                    .filter(Column("id") != endpoint.id)
                    .updateAll(db, Column("isDefault").set(to: false))
            }
            try endpoint.save(db)
        }
    }

    func deleteEndpoint(id: String) async throws {
        try await write { db in
            _ = try APIEndpointRecord.deleteOne(db, key: id)
        }
    }
}
