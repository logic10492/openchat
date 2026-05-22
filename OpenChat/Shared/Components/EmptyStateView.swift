import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: OpenChatDesignSystem.IconSize.emptyState, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(OpenChatDesignSystem.Typography.title)
            Text(message)
                .font(OpenChatDesignSystem.Typography.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
        }
        .padding(OpenChatDesignSystem.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.input, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.input, style: .continuous)
                .stroke(OpenChatDesignSystem.Surface.hairline, lineWidth: 0.5)
                .blendMode(.overlay)
        )
        .shadowElevation1()
        .padding(OpenChatDesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
