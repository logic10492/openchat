import SwiftUI

enum OpenChatDesignSystem {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let input: CGFloat = 24
    }

    enum IconSize {
        static let xs: CGFloat = 14
        static let sm: CGFloat = 16
        static let md: CGFloat = 20
        static let lg: CGFloat = 28
        static let avatar: CGFloat = 32
        static let emptyState: CGFloat = 48
    }

    enum Typography {
        static let largeTitle = Font.largeTitle.bold()
        static let title = Font.title2.bold()
        static let sectionTitle = Font.subheadline.weight(.semibold)
        static let rowTitle = Font.subheadline.weight(.medium)
        static let body = Font.body
        static let secondary = Font.subheadline
        static let metadata = Font.caption
        static let badge = Font.caption2.weight(.semibold)
        static let monoMetadata = Font.caption.monospacedDigit()
    }

    enum Surface {
        static let pageBackground = Color(.systemGroupedBackground)
        static let groupedBackground = Color(.secondarySystemGroupedBackground)
        static let sidebarControl = Color(.tertiarySystemBackground)
        static let subtleFill = Color(.systemGray5)
        static let disabledFill = Color(.systemGray3)
        static let accentWash = Color.accentColor.opacity(0.12)
        static let accentSoft = Color.accentColor.opacity(0.16)
        static let warningWash = Color.orange.opacity(0.15)
        static let reasoningWash = Color.purple.opacity(0.06)
        static let hairline = Color.white.opacity(0.16)
    }

    enum Shadow {
        static let elevation1 = [
            ShadowLayer(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2),
            ShadowLayer(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1),
        ]

        static let elevation2 = [
            ShadowLayer(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4),
            ShadowLayer(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1),
        ]

        static let elevation3 = [
            ShadowLayer(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8),
            ShadowLayer(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2),
        ]
    }

    enum ControlSize {
        static let iconButton: CGFloat = 36
        static let compactIconButton: CGFloat = 28
    }
}

struct ShadowLayer {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func shadowElevation1() -> some View {
        applyShadow(OpenChatDesignSystem.Shadow.elevation1)
    }

    func shadowElevation2() -> some View {
        applyShadow(OpenChatDesignSystem.Shadow.elevation2)
    }

    func shadowElevation3() -> some View {
        applyShadow(OpenChatDesignSystem.Shadow.elevation3)
    }

    func openChatCardStyle() -> some View {
        padding(OpenChatDesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.lg, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.lg, style: .continuous)
                    .stroke(OpenChatDesignSystem.Surface.hairline, lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadowElevation1()
    }

    func openChatGlassInputStyle() -> some View {
        padding(.horizontal, OpenChatDesignSystem.Spacing.md)
            .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.input, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.input, style: .continuous)
                    .stroke(OpenChatDesignSystem.Surface.hairline, lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadowElevation2()
    }

    func openChatInlineSectionTitle() -> some View {
        font(OpenChatDesignSystem.Typography.sectionTitle)
            .foregroundStyle(.secondary)
    }

    func openChatMessageStyle() -> some View {
        padding(.horizontal, OpenChatDesignSystem.Spacing.md)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
    }

    func openChatSidebarRow(isSelected: Bool) -> some View {
        padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.sm, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
            )
    }

    func openChatListRowStyle() -> some View {
        padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .contentShape(Rectangle())
    }

    func openChatInputStyle() -> some View {
        openChatGlassInputStyle()
    }

    func openChatPrimaryButtonStyle() -> some View {
        font(OpenChatDesignSystem.Typography.rowTitle)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.lg)
            .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
            .background(
                Color.accentColor,
                in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.md, style: .continuous)
            )
            .foregroundStyle(.white)
    }

    func openChatIconButtonFrame(size: CGFloat = OpenChatDesignSystem.ControlSize.iconButton) -> some View {
        frame(width: size, height: size)
    }

    func openChatBadgeStyle() -> some View {
        font(OpenChatDesignSystem.Typography.badge)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.xs)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
            .background(OpenChatDesignSystem.Surface.accentSoft, in: Capsule())
    }

    private func applyShadow(_ layers: [ShadowLayer]) -> some View {
        var view = AnyView(self)
        for layer in layers {
            view = AnyView(view.shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y))
        }
        return view
    }
}
