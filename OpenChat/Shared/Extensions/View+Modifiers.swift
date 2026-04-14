import SwiftUI

extension View {
    func openChatCardStyle() -> some View {
        padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func openChatInlineSectionTitle() -> some View {
        font(.headline)
            .foregroundStyle(.secondary)
    }

    func openChatMessageStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 4)
    }

    func openChatSidebarRow(isSelected: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color(.systemGray4)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    func openChatInputStyle() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }
}
