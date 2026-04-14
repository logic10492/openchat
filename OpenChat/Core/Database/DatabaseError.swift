import Foundation

enum DatabaseError: LocalizedError, @unchecked Sendable {
    case invalidPath(String)
    case directoryCreationFailed(URL, underlying: Error)
    case migrationFailed(underlying: Error)
    case operationFailed(underlying: Error)
    case exportFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPath(path):
            return "Invalid database path: \(path)"
        case let .directoryCreationFailed(url, underlying):
            return "Failed to create database directory at \(url.path): \(underlying.localizedDescription)"
        case let .migrationFailed(underlying):
            return "Database migration failed: \(underlying.localizedDescription)"
        case let .operationFailed(underlying):
            return "Database operation failed: \(underlying.localizedDescription)"
        case let .exportFailed(message):
            return "Export failed: \(message)"
        case let .importFailed(message):
            return "Import failed: \(message)"
        }
    }
}
