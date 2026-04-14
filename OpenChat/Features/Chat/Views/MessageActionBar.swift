import SwiftUI

struct MessageActionBar: View {
    let role: String
    let content: String
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

            if role == "assistant" {
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
        MessageActionBar(role: "assistant", content: "Hello", onRegenerate: {}, onDelete: {})
        MessageActionBar(role: "user", content: "Hi", onRegenerate: {}, onDelete: {})
    }
    .padding()
}
