import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    @Binding var isPrefillModeEnabled: Bool
    @Binding var inputRole: StageInputRole
    @Binding var responderIds: [String]
    var prefillNextRole: PrefillInputRole = .userMessage
    var stageParticipants: [StageParticipantRecord] = []
    var showsDirectorTools = false
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCustomizeResponders: () -> Void

    @State private var isDirectorPanelExpanded = false
    @State private var measuredInputHeight: CGFloat = 22
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private let minimumInputHeight: CGFloat = 22
    private let maximumInputHeight: CGFloat = 118

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeParticipants: [StageParticipantRecord] {
        stageParticipants
            .filter { $0.isActive && $0.visibilityValue == .present }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var chromeAppearance: ChatChromeAppearance {
        ChatChromeAppearance(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.xs) {
            if showsDirectorTools, isDirectorPanelExpanded {
                directorPanel
                    .frame(maxWidth: 920)
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !showsDirectorTools, isPrefillModeEnabled {
                prefillModeHint
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            composerRow
                .frame(maxWidth: 920)
                .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
        }
        .padding(.top, showsDirectorTools && isDirectorPanelExpanded ? OpenChatDesignSystem.Spacing.xs : OpenChatDesignSystem.Spacing.xxs)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.2), value: isDirectorPanelExpanded)
        .animation(.easeInOut(duration: 0.16), value: isFocused)
        .onChange(of: showsDirectorTools) { _, newValue in
            if !newValue {
                isDirectorPanelExpanded = false
                inputRole = .participant
            } else {
                isPrefillModeEnabled = false
            }
        }
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 7) {
            if showsDirectorTools {
                directorToolButton
                    .padding(.bottom, 4)
            } else {
                prefillMenu
                    .padding(.bottom, 4)
            }

            textInput

            sendButton
                .padding(.bottom, 4)
        }
    }

    private var prefillModeHint: some View {
        Text(prefillModeHintText)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 12)
            .accessibilityIdentifier("chat.prefillModeHint")
    }

    private var prefillModeHintText: String {
        switch prefillNextRole {
        case .userMessage:
            String(localized: "Prefill mode: this send saves as user input; the next one saves as a character reply.")
        case .assistantReply:
            String(localized: "Prefill mode: this send saves as a character reply; the next one saves as user input.")
        }
    }

    private var textInput: some View {
        ZStack(alignment: .topLeading) {
            inputMeasurer

            if text.isEmpty {
                Text(placeholder)
                    .font(OpenChatDesignSystem.Typography.body)
                    .foregroundStyle(chromeAppearance.placeholderText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(OpenChatDesignSystem.Typography.body)
                .foregroundStyle(chromeAppearance.primaryText)
                .frame(minHeight: editorHeight, maxHeight: editorHeight)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isFocused)
                .accessibilityIdentifier("chat.inputText")
        }
        .background {
            inputChromeBackground(shape: inputShape)
        }
        .overlay {
            inputShape
                .stroke(inputStroke, lineWidth: isFocused ? 1 : 0.5)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 9, x: 0, y: 3)
        .onPreferenceChange(InputTextHeightPreferenceKey.self) { height in
            measuredInputHeight = min(max(height, minimumInputHeight), maximumInputHeight)
        }
    }

    private var inputMeasurer: some View {
        Text(measurementText)
            .font(OpenChatDesignSystem.Typography.body)
            .lineLimit(1...6)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: InputTextHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
            .hidden()
    }

    private var measurementText: String {
        text.isEmpty ? " " : text + "\n"
    }

    private var editorHeight: CGFloat {
        min(max(measuredInputHeight - 6, minimumInputHeight), maximumInputHeight)
    }

    private var inputCornerRadius: CGFloat {
        min(22, (editorHeight + 14) / 2)
    }

    private var inputShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private func inputChromeBackground<S: Shape>(shape: S) -> some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(inputGlassTint(appearance: chromeAppearance))
                .glassEffect(.regular.tint(inputGlassTint(appearance: chromeAppearance)).interactive(), in: shape)
        } else {
            shape.fill(chromeAppearance.fallbackFill)
        }
    }

    private var placeholder: String {
        if showsDirectorTools, inputRole.isDirectorInstructionInput {
            return String(localized: "Director instruction")
        }
        if !showsDirectorTools, isPrefillModeEnabled {
            switch prefillNextRole {
            case .userMessage:
                return String(localized: "User message")
            case .assistantReply:
                return String(localized: "Character reply")
            }
        }
        return String(localized: "Message")
    }

    private var inputStroke: Color {
        isFocused ? Color.accentColor.opacity(0.34) : chromeAppearance.stroke
    }

    private var directorToolButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isDirectorPanelExpanded.toggle()
        } label: {
            Image(systemName: isDirectorPanelExpanded ? "ellipsis.circle.fill" : "ellipsis.circle")
                .font(.system(size: 29, weight: .regular))
                .foregroundStyle(isDirectorPanelExpanded ? Color.accentColor : chromeAppearance.secondaryText)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Director Tools"))
        .accessibilityIdentifier("chat.directorToolsButton")
    }

    private var prefillMenu: some View {
        Menu {
            Button {
                isPrefillModeEnabled = false
            } label: {
                Label(String(localized: "User message"), systemImage: "person")
            }
            .disabled(!isPrefillModeEnabled)
            .accessibilityIdentifier("chat.inputMode.userMessage")

            Button {
                isPrefillModeEnabled = true
            } label: {
                Label(String(localized: "Prefill dialogue"), systemImage: "quote.bubble")
            }
            .disabled(isPrefillModeEnabled)
            .accessibilityIdentifier("chat.inputMode.prefill")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isPrefillModeEnabled ? Color.accentColor : chromeAppearance.secondaryText)
                .frame(width: 34, height: 34)
                .background {
                    inputModeMenuGlassFill(isActive: isPrefillModeEnabled)
                }
                .overlay {
                    inputModeMenuGlassStroke(isActive: isPrefillModeEnabled)
                }
                .shadow(color: chromeAppearance.shadow.opacity(isPrefillModeEnabled ? 1.2 : 0.7), radius: 8, x: 0, y: 3)
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Input Mode"))
        .accessibilityValue(isPrefillModeEnabled ? String(localized: "Prefill dialogue") : String(localized: "User message"))
        .accessibilityIdentifier("chat.inputModeMenu")
    }

    private var directorPanel: some View {
        DirectorResponderPanel(
            inputRole: $inputRole,
            responderIds: $responderIds,
            activeParticipants: activeParticipants,
            onCollapse: {
                isDirectorPanelExpanded = false
            },
            onCustomizeResponders: onCustomizeResponders
        )
    }

    @ViewBuilder
    private var sendButton: some View {
        if isGenerating {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStop()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: OpenChatDesignSystem.IconSize.sm, weight: .bold))
                    .foregroundStyle(chromeAppearance.primaryText)
                    .frame(width: 34, height: 34)
                    .background {
                        sendButtonGlassFill(isEnabled: true)
                    }
                    .overlay {
                        sendButtonGlassStroke(isEnabled: true)
                    }
                    .shadow(color: chromeAppearance.shadow, radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop generating"))
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSend()
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: OpenChatDesignSystem.IconSize.md, weight: .bold))
                    .foregroundStyle(canSend ? Color.accentColor : chromeAppearance.secondaryText)
                    .frame(width: 34, height: 34)
                    .background {
                        sendButtonGlassFill(isEnabled: canSend)
                    }
                    .overlay {
                        sendButtonGlassStroke(isEnabled: canSend)
                    }
                    .shadow(color: chromeAppearance.shadow.opacity(canSend ? 1.2 : 0.7), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send message"))
            .accessibilityIdentifier("chat.sendButton")
        }
    }

    @ViewBuilder
    private func sendButtonGlassFill(isEnabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(sendButtonGlassTint(isEnabled: isEnabled, appearance: chromeAppearance))
                .glassEffect(.regular.tint(sendButtonGlassTint(isEnabled: isEnabled, appearance: chromeAppearance)).interactive(), in: Circle())
        } else {
            Circle()
                .fill(chromeAppearance.fallbackFill)
        }
    }

    private func sendButtonGlassStroke(isEnabled: Bool) -> some View {
        Circle()
            .stroke(
                isEnabled ? Color.accentColor.opacity(0.34) : chromeAppearance.stroke,
                lineWidth: 0.8
            )
    }

    @ViewBuilder
    private func inputModeMenuGlassFill(isActive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(inputModeMenuGlassTint(isActive: isActive, appearance: chromeAppearance))
                .glassEffect(.regular.tint(inputModeMenuGlassTint(isActive: isActive, appearance: chromeAppearance)).interactive(), in: Circle())
        } else {
            Circle()
                .fill(chromeAppearance.fallbackFill)
        }
    }

    private func inputModeMenuGlassStroke(isActive: Bool) -> some View {
        Circle()
            .stroke(
                isActive ? Color.accentColor.opacity(0.38) : chromeAppearance.stroke,
                lineWidth: 0.8
            )
    }

    private func inputGlassTint(appearance: ChatChromeAppearance) -> Color {
        if colorScheme == .dark {
            return Color.black.opacity(isFocused ? 0.34 : 0.28)
        }
        return Color.white.opacity(isFocused ? 0.34 : 0.28)
    }

    private func sendButtonGlassTint(isEnabled: Bool, appearance: ChatChromeAppearance) -> Color {
        if isEnabled {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.18)
        }
        return appearance.glassTint
    }

    private func inputModeMenuGlassTint(isActive: Bool, appearance: ChatChromeAppearance) -> Color {
        if isActive {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.20)
        }
        return appearance.glassTint
    }
}

#Preview("Stage Composer") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant("Set the next beat, then let Mara answer."),
            isPrefillModeEnabled: .constant(false),
            inputRole: .constant(.participant),
            responderIds: .constant(["stage-participant-mara", "stage-participant-io"]),
            prefillNextRole: .userMessage,
            stageParticipants: [
                StageParticipantRecord(
                    id: "stage-participant-mara",
                    stageId: "stage-preview",
                    characterCardId: "mara",
                    displayName: "Mara",
                    visibility: StageParticipantVisibility.present.rawValue,
                    isActive: true,
                    sortOrder: 0,
                    createdAt: .now,
                    updatedAt: .now
                ),
                StageParticipantRecord(
                    id: "stage-participant-io",
                    stageId: "stage-preview",
                    characterCardId: "io",
                    displayName: "Io",
                    visibility: StageParticipantVisibility.present.rawValue,
                    isActive: true,
                    sortOrder: 1,
                    createdAt: .now,
                    updatedAt: .now
                ),
            ],
            showsDirectorTools: true,
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
    .background(OpenChatDesignSystem.Surface.pageBackground)
}

private struct InputTextHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 22

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
