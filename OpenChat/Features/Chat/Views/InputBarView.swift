import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(String(localized: "Message"), text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: isGenerating ? onStop : onSend) {
                Image(systemName: isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(!isGenerating && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
