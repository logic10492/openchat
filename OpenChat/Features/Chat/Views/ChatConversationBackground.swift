import SwiftUI

struct ChatConversationBackground: View {
    let isGenerating: Bool
    let isEnabled: Bool
    let isTimelineScrolling: Bool

    var body: some View {
        Group {
            if isEnabled {
                VibeBackgroundView(
                    isGenerating: isGenerating,
                    isTimelineScrolling: isTimelineScrolling
                )
            } else {
                OpenChatDesignSystem.Surface.pageBackground
            }
        }
        .background(OpenChatDesignSystem.Surface.pageBackground)
        .ignoresSafeArea()
    }
}
