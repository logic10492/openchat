import SwiftUI

struct MessageActionBar: View {
    let content: String
    var showsRegenerate = true
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = content
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel(String(localized: "Copy"))

            if showsRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "Regenerate"))
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(String(localized: "Delete"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        MessageActionBar(content: "Hello", onRegenerate: {}, onDelete: {})
    }
    .padding()
}
