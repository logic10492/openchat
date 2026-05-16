import SwiftUI

struct DataManagementView: View {
    @State var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Button(String(localized: "Clear Chats and Content"), role: .destructive) {
                Task { await viewModel.clearAllData() }
            }

            Text(String(localized: "Export and import will be enabled after the full data snapshot pipeline is wired."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
