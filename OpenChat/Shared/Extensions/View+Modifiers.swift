import SwiftUI

extension View {
    // 阴影层级预设
    func shadowElevation1() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
    }
    
    func shadowElevation2() -> some View {
        self.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    func shadowElevation3() -> some View {
        self.shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // 基础磨砂卡片
    func openChatCardStyle() -> some View {
        padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadowElevation1()
    }

    // 悬浮磨砂胶囊风格（如 InputBar）
    func openChatGlassInputStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadowElevation2()
    }

    func openChatInlineSectionTitle() -> some View {
        font(.headline)
            .foregroundStyle(.secondary)
    }

    func openChatMessageStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 4)
    }

    // 侧边栏及选中状态样式，更加柔和
    func openChatSidebarRow(isSelected: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
            )
    }

    // 遗留方法重定向至新的胶囊风格
    func openChatInputStyle() -> some View {
        openChatGlassInputStyle()
    }
}
