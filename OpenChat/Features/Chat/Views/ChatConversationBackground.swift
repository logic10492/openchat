import SwiftUI

struct ChatConversationBackground: View {
    let isGenerating: Bool
    let isEnabled: Bool

    var body: some View {
        Group {
            if isEnabled {
                VibeBackgroundView(isGenerating: isGenerating)
            } else {
                OpenChatDesignSystem.Surface.pageBackground
            }
        }
        .background(OpenChatDesignSystem.Surface.pageBackground)
        .ignoresSafeArea()
    }
}
