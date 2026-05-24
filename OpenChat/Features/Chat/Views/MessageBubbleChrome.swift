import SwiftUI

struct MessageTimestampFooter: View {
    let date: Date
    let isStreaming: Bool
    var isOutgoing = false

    var body: some View {
        HStack(spacing: 4) {
            Text(date.openChatRelativeTimestamp())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.72) : Color(.tertiaryLabel))
            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .tint(isOutgoing ? .white : .primary)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SystemMessageBubble: View {
    let content: String
    let copyContent: String

    var body: some View {
        Text(content)
            .font(OpenChatDesignSystem.Typography.metadata)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = copyContent
                } label: {
                    Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                }
            }
    }
}
