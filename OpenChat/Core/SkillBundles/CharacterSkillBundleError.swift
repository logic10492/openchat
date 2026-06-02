import Foundation

enum CharacterSkillBundleError: LocalizedError, Sendable {
    case unsafePath(String)
    case duplicateFilePath(String)
    case storageDirectoryUnavailable
    case directoryCreationFailed(URL, underlying: Error)
    case fileReadFailed(URL, underlying: Error)
    case fileWriteFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            "Unsafe skill bundle path rejected: \(path)"
        case .duplicateFilePath(let path):
            "Duplicate skill bundle file path rejected: \(path)"
        case .storageDirectoryUnavailable:
            "Application Support directory is unavailable."
        case .directoryCreationFailed(let url, let underlying):
            "Failed to create skill bundle directory at \(url.path): \(underlying.localizedDescription)"
        case .fileReadFailed(let url, let underlying):
            "Failed to read skill bundle file at \(url.path): \(underlying.localizedDescription)"
        case .fileWriteFailed(let url, let underlying):
            "Failed to write skill bundle file at \(url.path): \(underlying.localizedDescription)"
        }
    }
}
