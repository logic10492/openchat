import Foundation

enum AppRoute: Hashable, Identifiable {
    case conversation(String)
    case characterCard(String)
    case worldBook(String)
    case characters
    case worldBooks

    var id: String {
        switch self {
        case .conversation(let id), .characterCard(let id), .worldBook(let id):
            id
        case .characters:
            "characters"
        case .worldBooks:
            "worldBooks"
        }
    }
}

enum AppSheet: String, Identifiable {
    case settings
    case chatSettings
    case characterEditor
    case worldBookImport

    var id: String { rawValue }
}

enum AppAlert: String, Identifiable {
    case destructiveDelete
    case exportWarning

    var id: String { rawValue }
}
