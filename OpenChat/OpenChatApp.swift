import SwiftUI

@main
struct OpenChatApp: App {
    @State private var dependencyContainer: DependencyContainer
    @State private var appState = AppState()

    init() {
        let container = (try? DependencyContainer.live()) ?? DependencyContainer.preview()
        _dependencyContainer = State(initialValue: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(dependencyContainer)
        }
    }
}
