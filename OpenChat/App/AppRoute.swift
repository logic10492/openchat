import Foundation

enum AppRoute: Hashable, Identifiable {
    case conversation(String)
    case characterCard(String)
    case worldBook(String)

    var id: String {
        switch self {
        case .conversation(let id), .characterCard(let id), .worldBook(let id):
            id
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
