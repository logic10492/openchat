import Foundation
import Observation
import SwiftUI

@Observable
final class AppState {
    enum SidebarDestination: Hashable {
        case conversations
        case characters
        case worldBooks
    }

    var sidebarDestination: SidebarDestination = .conversations
    var columnVisibility: NavigationSplitViewVisibility = .automatic
    var selectedConversationID: String?
    var selectedCharacterCardID: String?
    var selectedWorldBookID: String?
    var isShowingSettings = false
    var isShowingError = false
    var lastErrorMessage: String?
    var conversationListNeedsRefresh = false

    func present(error message: String) {
        lastErrorMessage = message
        isShowingError = true
    }
}
