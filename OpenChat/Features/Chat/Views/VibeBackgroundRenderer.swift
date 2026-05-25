import SwiftUI

struct VibeBackgroundRenderer: View {
    let phase: VibeBackgroundPhase
    let phaseStartedAt: Date
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let reduceTransparency: Bool

    private let renderScale: CGFloat = 0.25
    private let horizontalOverscan: CGFloat = 1.85
    private let verticalOverscan: CGFloat = 1.25
    private let blurRadius: CGFloat = 36

    var body: some View {
        GeometryReader { proxy in
            let visibleRenderSize = CGSize(
                width: max(96, ceil(proxy.size.width * renderScale)),
                height: max(160, ceil(proxy.size.height * renderScale))
            )
            let renderSize = CGSize(
                width: max(192, ceil(visibleRenderSize.width * horizontalOverscan)),
                height: max(220, ceil(visibleRenderSize.height * verticalOverscan))
            )
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : phase.frameInterval)) { timeline in
                VibeBackgroundCanvas(
                    phase: phase,
                    phaseStartedAt: phaseStartedAt,
                    date: reduceMotion ? phaseStartedAt : timeline.date,
                    palette: VibeBackgroundPalette(colorScheme: colorScheme),
                    reduceMotion: reduceMotion
                )
                .frame(width: renderSize.width, height: renderSize.height)
                .scaleEffect(1 / renderScale)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .transaction { transaction in
                    transaction.animation = nil
                }
                .blur(radius: reduceTransparency ? 22 : blurRadius)
                .saturation(colorScheme == .dark ? 1.25 : 1.08)
                .brightness(colorScheme == .dark ? -0.02 : 0.06)
                .overlay {
                    VibeBackgroundShade(
                        colorScheme: colorScheme,
                        reduceTransparency: reduceTransparency
                    )
                }
            }
        }
    }
}
