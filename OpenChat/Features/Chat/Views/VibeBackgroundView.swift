import SwiftUI

struct VibeBackgroundView: View {
    let isGenerating: Bool
    let isTimelineScrolling: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VibeBackgroundUIKitRepresentable(
            isGenerating: isGenerating,
            isTimelineScrolling: isTimelineScrolling,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            colorScheme: colorScheme
        )
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

#Preview("Night") {
    VibeBackgroundView(isGenerating: true, isTimelineScrolling: false)
        .preferredColorScheme(.dark)
}

#Preview("Day") {
    VibeBackgroundView(isGenerating: true, isTimelineScrolling: false)
        .preferredColorScheme(.light)
}
