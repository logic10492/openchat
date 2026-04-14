import SwiftUI

struct DataManagementView: View {
    @State var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(String(localized: "Clear Chats and Content"), role: .destructive) {
                Task { await viewModel.clearAllData() }
            }

            Text(String(localized: "Export and import will be enabled after the full data snapshot pipeline is wired."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
