import SwiftUI

@main
struct OpenChatApp: App {
    @State private var startupState: StartupState
    @State private var appState = AppState()

    init() {
        do {
            if UITestingSupport.isEnabled {
                let testing = try UITestingSupport.makeContainer()
                _startupState = State(initialValue: .ready(testing.0))
                _appState = State(initialValue: testing.1)
            } else {
                _startupState = State(initialValue: .ready(try DependencyContainer.live()))
            }
        } catch {
            _startupState = State(initialValue: .failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startupState {
            case .ready(let dependencyContainer):
                ContentView()
                    .environment(appState)
                    .environment(dependencyContainer)
            case .failed(let message):
                StartupErrorView(message: message) {
                    retryStartup()
                }
            }
        }
    }

    private func retryStartup() {
        do {
            startupState = .ready(try DependencyContainer.live())
        } catch {
            startupState = .failed(error.localizedDescription)
        }
    }
}

private enum StartupState {
    case ready(DependencyContainer)
    case failed(String)
}

private struct StartupErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "OpenChat Could Not Start"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "Retry"), action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
