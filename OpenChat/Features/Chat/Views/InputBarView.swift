import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    @Binding var inputRole: StageInputRole
    var showsDirectorToggle = false
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsDirectorToggle {
                Picker(String(localized: "Input Role"), selection: $inputRole) {
                    Label(String(localized: "Participant"), systemImage: "person.fill")
                        .tag(StageInputRole.participant)
                    Label(String(localized: "Director"), systemImage: "theatermasks.fill")
                        .tag(StageInputRole.director)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Input Role"))
            }

            HStack(alignment: .bottom, spacing: 0) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($isFocused)

                sendButton
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var placeholder: String {
        inputRole.isDirectorInstructionInput
            ? String(localized: "Director instruction")
            : String(localized: "Message")
    }

    @ViewBuilder
    private var sendButton: some View {
        if isGenerating {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStop()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(String(localized: "Stop generating"))
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSend()
            }) {
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
            inputRole: .constant(.participant),
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
            inputRole: .constant(.participant),
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
            inputRole: .constant(.participant),
            isGenerating: true,
            onSend: {},
            onStop: {}
        )
    }
}
