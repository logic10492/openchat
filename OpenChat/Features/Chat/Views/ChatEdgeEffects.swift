import SwiftUI

struct ChatEdgeEffectViewport<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .accessibilityIdentifier("chat.edgeEffectViewport")
        } else {
            GeometryReader { proxy in
                let topHeight = min(56, proxy.size.height * 0.12)
                let bottomHeight = min(68, proxy.size.height * 0.14)

                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask {
                        ChatEdgeContentFadeMask(topHeight: topHeight, bottomHeight: bottomHeight)
                    }
                    .overlay(alignment: .top) {
                        ChatFallbackEdgeBlurBand(edge: .top, height: topHeight)
                    }
                    .overlay(alignment: .bottom) {
                        ChatFallbackEdgeBlurBand(edge: .bottom, height: bottomHeight)
                    }
            }
            .accessibilityIdentifier("chat.edgeEffectViewport")
        }
    }
}

private struct ChatEdgeContentFadeMask: View {
    let topHeight: CGFloat
    let bottomHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ChatEdgeContentFadeBand(edge: .top)
                .frame(height: topHeight)

            Rectangle()
                .fill(.black)

            ChatEdgeContentFadeBand(edge: .bottom)
                .frame(height: bottomHeight)
        }
    }
}

private struct ChatEdgeContentFadeBand: View {
    let edge: VerticalEdge

    var body: some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var stops: [Gradient.Stop] {
        switch edge {
        case .top:
            return [
                .init(color: .black.opacity(0.18), location: 0.00),
                .init(color: .black.opacity(0.44), location: 0.22),
                .init(color: .black.opacity(0.78), location: 0.58),
                .init(color: .black.opacity(1.00), location: 1.00),
            ]
        case .bottom:
            return [
                .init(color: .black.opacity(1.00), location: 0.00),
                .init(color: .black.opacity(0.78), location: 0.42),
                .init(color: .black.opacity(0.44), location: 0.78),
                .init(color: .black.opacity(0.18), location: 1.00),
            ]
        }
    }
}

private struct ChatFallbackEdgeBlurBand: View {
    let edge: VerticalEdge
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(0.58)
            .mask {
                ChatEdgeMaterialMask(edge: edge)
            }
            .frame(height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ChatEdgeMaterialMask: View {
    let edge: VerticalEdge

    var body: some View {
        LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private var stops: [Gradient.Stop] {
        switch edge {
        case .top:
            return [
                .init(color: .black.opacity(0.42), location: 0.00),
                .init(color: .black.opacity(0.28), location: 0.24),
                .init(color: .black.opacity(0.10), location: 0.62),
                .init(color: .black.opacity(0.00), location: 1.00),
            ]
        case .bottom:
            return [
                .init(color: .black.opacity(0.00), location: 0.00),
                .init(color: .black.opacity(0.10), location: 0.38),
                .init(color: .black.opacity(0.28), location: 0.76),
                .init(color: .black.opacity(0.42), location: 1.00),
            ]
        }
    }
}

extension View {
    @ViewBuilder
    func openChatScrollEdgeEffects() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }

    @ViewBuilder
    func chatInputBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: content)
        }
    }
}
