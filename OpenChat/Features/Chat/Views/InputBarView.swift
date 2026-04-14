import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 0) {
                TextField(String(localized: "Message"), text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($isFocused)

                sendButton
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var sendButton: some View {
        if isGenerating {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(String(localized: "Stop generating"))
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.primary : Color(.systemGray3))
            }
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send message"))
        }
    }
}

#Preview {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            isGenerating: false,
            onSend: {},
            onStop: {}
        )
    }
}

#Preview("With text") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant("Hello, how are you?"),
            isGenerating: false,
            onSend: {},
            onStop: {}
        )
    }
}

#Preview("Generating") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            isGenerating: true,
            onSend: {},
            onStop: {}
        )
    }
}
