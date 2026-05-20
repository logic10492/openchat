import SwiftUI

struct DataManagementView: View {
    @State var viewModel: SettingsViewModel
    @State private var showClearDataConfirmation = false

    var body: some View {
        Section(String(localized: "World Book Semantic Index")) {
            Button {
                Task { await viewModel.rebuildWorldBookSemanticIndex() }
            } label: {
                Label(
                    viewModel.isRebuildingWorldBookIndex
                        ? String(localized: "Rebuilding World Book Semantic Index...")
                        : String(localized: "Rebuild World Book Semantic Index"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(viewModel.isRebuildingWorldBookIndex)

            if let message = viewModel.worldBookIndexStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section(String(localized: "Data Export")) {
            Text(String(localized: "Export and import will be enabled after the full data snapshot pipeline is wired."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section(String(localized: "Danger Zone")) {
            Button(String(localized: "Clear Conversations, Characters, and World Books"), role: .destructive) {
                showClearDataConfirmation = true
            }
        }
        .confirmationDialog(
            String(localized: "Clear All Data?"),
            isPresented: $showClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear Conversations, Characters, and World Books"), role: .destructive) {
                Task { await viewModel.clearAllData() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will delete conversations, character cards, world books, world book entries, memories, and messages. API endpoints are kept. This action cannot be undone."))
        }
    }
}
