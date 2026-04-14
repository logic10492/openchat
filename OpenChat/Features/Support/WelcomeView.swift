import SwiftUI

struct WelcomeView: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(String(localized: "OpenChat"))
                    .font(.largeTitle.bold())
                Text(String(localized: "Start a new conversation to begin."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button(action: onNewChat) {
                HStack {
                    Image(systemName: "plus")
                    Text(String(localized: "New Chat"))
                }
                .fontWeight(.medium)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
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
