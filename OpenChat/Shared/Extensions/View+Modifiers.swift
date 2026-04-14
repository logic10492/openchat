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
}
