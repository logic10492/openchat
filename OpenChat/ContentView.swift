import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        TabView(selection: binding(\.selectedTab)) {
            ConversationListView(
                viewModel: ConversationListViewModel(
                    databaseManager: container.databaseManager,
                    appState: appState
                )
            )
            .tabItem {
                Label(String(localized: "Chats"), systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppState.Tab.chats)

            CharacterCardListView(
                viewModel: CharacterCardListViewModel(
                    databaseManager: container.databaseManager,
                    appState: appState
                )
            )
            .tabItem {
                Label(String(localized: "Characters"), systemImage: "person.text.rectangle")
            }
            .tag(AppState.Tab.characters)

            WorldBookListView(
                viewModel: WorldBookListViewModel(
                    databaseManager: container.databaseManager,
                    appState: appState
                )
            )
            .tabItem {
                Label(String(localized: "World Books"), systemImage: "books.vertical")
            }
            .tag(AppState.Tab.worldBooks)

            SettingsView(
                viewModel: SettingsViewModel(
                    databaseManager: container.databaseManager,
                    apiClient: container.apiClient,
                    appState: appState
                )
            )
            .tabItem {
                Label(String(localized: "Settings"), systemImage: "gearshape")
            }
            .tag(AppState.Tab.settings)
        }
        .alert(
            String(localized: "Error"),
            isPresented: binding(\.isShowingError)
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                appState.isShowingError = false
                appState.lastErrorMessage = nil
            }
        } message: {
            Text(appState.lastErrorMessage ?? String(localized: "Unknown error"))
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>) -> Binding<Value> {
        @Bindable var appState = appState
        return Binding(
            get: { appState[keyPath: keyPath] },
            set: { appState[keyPath: keyPath] = $0 }
        )
    }
}
