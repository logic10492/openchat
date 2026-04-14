import SwiftUI

struct LoadingIndicator: View {
    let title: String

    init(_ title: String = String(localized: "Loading")) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
