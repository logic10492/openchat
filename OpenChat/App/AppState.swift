import Foundation
import Observation

@Observable
final class AppState {
    enum Tab: Hashable {
        case chats
        case characters
        case worldBooks
        case settings
    }

    var selectedTab: Tab = .chats
    var selectedConversationID: String?
    var selectedCharacterCardID: String?
    var selectedWorldBookID: String?
    var isShowingError = false
    var lastErrorMessage: String?

    func present(error message: String) {
        lastErrorMessage = message
        isShowingError = true
    }
}
