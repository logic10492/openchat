import SwiftUI

struct MemoryMarkerView: View {
    let item: MessageDisplayItem

    private var isError: Bool { item.role == "memory-error" }

    var body: some View {
        Text(item.content)
            .font(.caption.italic())
            .foregroundStyle(isError ? .red.opacity(0.7) : .secondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 32)
    }
}

#Preview("Success") {
    MemoryMarkerView(
        item: .memoryMarker(content: "🧠 Memorized 3 entries\n· Player saved the elf in the forest\n· The dragon revealed its true name\n· Alliance formed with the mountain clan")
    )
}

#Preview("Error") {
    MemoryMarkerView(
        item: .memoryMarker(content: "🧠 Memory extraction failed\nFailed to parse extraction response: dataCorrupted", isError: true)
    )
}
