import SwiftUI

struct WelcomeView: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.lg) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: OpenChatDesignSystem.Spacing.xs) {
                Text(String(localized: "OpenChat"))
                    .font(OpenChatDesignSystem.Typography.largeTitle)
                Text(String(localized: "Start a new conversation to begin."))
                    .font(OpenChatDesignSystem.Typography.body)
                    .foregroundStyle(.secondary)
            }

            Button(action: onNewChat) {
                HStack {
                    Image(systemName: "plus")
                    Text(String(localized: "New Chat"))
                }
                .openChatPrimaryButtonStyle()
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView(onNewChat: {})
}
