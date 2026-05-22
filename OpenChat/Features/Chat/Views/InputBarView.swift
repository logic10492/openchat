import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    @Binding var inputRole: StageInputRole
    @Binding var responderIds: [String]
    var stageParticipants: [StageParticipantRecord] = []
    var showsDirectorTools = false
    let isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCustomizeResponders: () -> Void
    @State private var isDirectorPanelExpanded = false
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var activeParticipants: [StageParticipantRecord] {
        stageParticipants
            .filter { $0.isActive && $0.visibilityValue == .present }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var panelParticipants: [StageParticipantRecord] {
        let selected = responderIds.compactMap { id in
            activeParticipants.first { $0.id == id }
        }
        let selectedIds = Set(selected.map(\.id))
        return selected + activeParticipants.filter { !selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.xs) {
            if showsDirectorTools, isDirectorPanelExpanded {
                directorPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 0) {
                if showsDirectorTools {
                    directorToolButton
                        .padding(.leading, OpenChatDesignSystem.Spacing.xs)
                        .padding(.bottom, OpenChatDesignSystem.Spacing.xs)
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
                    .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
                    .focused($isFocused)
                    .accessibilityIdentifier("chat.inputText")

                sendButton
                    .padding(.trailing, OpenChatDesignSystem.Spacing.xs)
                    .padding(.bottom, OpenChatDesignSystem.Spacing.xs)
            }
        }
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
        .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
        .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
        .animation(.easeInOut(duration: 0.2), value: isDirectorPanelExpanded)
        .onChange(of: showsDirectorTools) { _, newValue in
            if !newValue {
                isDirectorPanelExpanded = false
                inputRole = .participant
            }
        }
    }

    private var placeholder: String {
        String(localized: "Message")
    }

    private var directorToolButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            inputRole = .participant
            isDirectorPanelExpanded.toggle()
        } label: {
                Image(systemName: isDirectorPanelExpanded ? "theatermasks.fill" : "theatermasks")
                    .font(.system(size: 22))
                    .openChatIconButtonFrame()
                    .foregroundStyle(isDirectorPanelExpanded ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel(String(localized: "Director Tools"))
        .accessibilityIdentifier("chat.directorToolsButton")
    }

    private var directorPanel: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.sm) {
            HStack {
                Label(String(localized: "Response Order"), systemImage: "list.number")
                    .font(OpenChatDesignSystem.Typography.badge)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("chat.directorToolsPanel")
                Spacer()
                Button {
                    isDirectorPanelExpanded = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .openChatIconButtonFrame(size: OpenChatDesignSystem.ControlSize.compactIconButton)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Collapse Director Tools"))
                .accessibilityIdentifier("chat.directorToolsCollapse")
            }

            if activeParticipants.isEmpty {
                Text(String(localized: "No active stage participants"))
                    .font(OpenChatDesignSystem.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
            } else {
                VStack(spacing: 6) {
                    ForEach(panelParticipants) { participant in
                        responderRow(participant)
                    }
                }
            }
        }
        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
        .padding(.top, OpenChatDesignSystem.Spacing.sm)
    }

    private func responderRow(_ participant: StageParticipantRecord) -> some View {
        let selected = responderIds.contains(participant.id)
        let index = responderIds.firstIndex(of: participant.id)
        return HStack(spacing: OpenChatDesignSystem.Spacing.xs) {
            Button {
                toggleResponder(participant)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: OpenChatDesignSystem.IconSize.md))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .openChatIconButtonFrame(size: OpenChatDesignSystem.IconSize.avatar)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(participant.displayName)
            .accessibilityIdentifier("chat.directorResponder.\(participant.displayName)")

            Text(participant.displayName)
                .font(OpenChatDesignSystem.Typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let index {
                Text(String(localized: "Order \(index + 1)"))
                    .font(OpenChatDesignSystem.Typography.monoMetadata)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("chat.directorResponderOrder.\(participant.displayName)")
            }

            Button {
                moveResponder(participant, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .openChatIconButtonFrame(size: OpenChatDesignSystem.ControlSize.compactIconButton)
            }
            .buttonStyle(.plain)
            .disabled(index == nil || index == 0)
            .accessibilityLabel(String(localized: "Move responder up"))
            .accessibilityIdentifier("chat.directorResponderUp.\(participant.displayName)")

            Button {
                moveResponder(participant, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .openChatIconButtonFrame(size: OpenChatDesignSystem.ControlSize.compactIconButton)
            }
            .buttonStyle(.plain)
            .disabled(index == nil || index == responderIds.count - 1)
            .accessibilityLabel(String(localized: "Move responder down"))
            .accessibilityIdentifier("chat.directorResponderDown.\(participant.displayName)")
        }
        .padding(.vertical, 2)
    }

    private func toggleResponder(_ participant: StageParticipantRecord) {
        inputRole = .participant
        if let index = responderIds.firstIndex(of: participant.id) {
            guard responderIds.count > 1 else { return }
            onCustomizeResponders()
            responderIds.remove(at: index)
        } else {
            onCustomizeResponders()
            responderIds.append(participant.id)
        }
    }

    private func moveResponder(_ participant: StageParticipantRecord, offset: Int) {
        guard let index = responderIds.firstIndex(of: participant.id) else { return }
        let target = index + offset
        guard responderIds.indices.contains(target) else { return }
        onCustomizeResponders()
        responderIds.swapAt(index, target)
    }

    @ViewBuilder
    private var sendButton: some View {
        if isGenerating {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStop()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: OpenChatDesignSystem.IconSize.lg))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(String(localized: "Stop generating"))
        } else {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSend()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: OpenChatDesignSystem.IconSize.lg))
                    .foregroundStyle(canSend ? Color.primary : OpenChatDesignSystem.Surface.disabledFill)
            }
            .disabled(!canSend)
            .accessibilityLabel(String(localized: "Send message"))
            .accessibilityIdentifier("chat.sendButton")
        }
    }

}

#Preview {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
}

#Preview("With text") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant("Hello, how are you?"),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: false,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
}

#Preview("Generating") {
    VStack {
        Spacer()
        InputBarView(
            text: .constant(""),
            inputRole: .constant(.participant),
            responderIds: .constant([]),
            isGenerating: true,
            onSend: {},
            onStop: {},
            onCustomizeResponders: {}
        )
    }
}
