import SwiftUI

struct VibeBackgroundUIKitRepresentable: UIViewRepresentable {
    let isGenerating: Bool
    let isTimelineScrolling: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> VibeBackgroundUIKitView {
        let view = VibeBackgroundUIKitView()
        view.configure(
            isGenerating: isGenerating,
            isTimelineScrolling: isTimelineScrolling,
            colorScheme: colorScheme,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
        return view
    }

    func updateUIView(_ uiView: VibeBackgroundUIKitView, context: Context) {
        uiView.configure(
            isGenerating: isGenerating,
            isTimelineScrolling: isTimelineScrolling,
            colorScheme: colorScheme,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }
}
