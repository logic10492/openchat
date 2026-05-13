import Foundation
import GRDB
import SqliteVec

final class DatabaseManager: @unchecked Sendable {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        let configuration = Self.makeConfiguration()
        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Migrations.makeMigrator().migrate(dbQueue)
    }

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            if let connection = db.sqliteConnection {
                registerSqliteVec(connection)
            }
        }
        try Migrations.makeMigrator().migrate(dbQueue)
    }

    static func live() throws -> DatabaseManager {
        let url = try databaseURL()
        return try DatabaseManager(path: url.path)
    }

    static func inMemory() throws -> DatabaseManager {
        try DatabaseManager(dbQueue: DatabaseQueue())
    }

    func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }

    func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }

    func eraseAllData(preserveEndpoints: Bool = true) async throws {
        try await write { db in
            try db.execute(sql: "DELETE FROM memory_embedding")
            try MessageRecord.deleteAll(db)
            try ConversationRecord.deleteAll(db)
            try WorldBookEntryRecord.deleteAll(db)
            try WorldBookRecord.deleteAll(db)
            try CharacterCardRecord.deleteAll(db)
            if !preserveEndpoints {
                try APIEndpointRecord.deleteAll(db)
            }
        }
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            if let connection = db.sqliteConnection {
                registerSqliteVec(connection)
            }
        }
        return configuration
    }

    private static func databaseURL() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.invalidPath("Application Support directory is unavailable")
        }
        let directory = baseURL.appending(path: "OpenChat", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw DatabaseError.directoryCreationFailed(directory, underlying: error)
        }
        return directory.appending(path: "database.sqlite")
    }
}
