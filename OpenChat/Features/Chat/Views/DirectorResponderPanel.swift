import SwiftUI

struct DirectorResponderPanel: View {
    @Binding var inputRole: StageInputRole
    @Binding var responderIds: [String]
    let activeParticipants: [StageParticipantRecord]
    let onCollapse: () -> Void
    let onCustomizeResponders: () -> Void

    private var panelParticipants: [StageParticipantRecord] {
        let selected = responderIds.compactMap { id in
            activeParticipants.first { $0.id == id }
        }
        let selectedIds = Set(selected.map(\.id))
        return selected + activeParticipants.filter { !selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.sm) {
            header
            inputModePicker
            content
        }
        .padding(OpenChatDesignSystem.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.lg, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.lg, style: .continuous)
                .stroke(Color(.separator).opacity(0.16), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack {
            Label(String(localized: "Stage Controls"), systemImage: "theatermasks")
                .font(OpenChatDesignSystem.Typography.badge)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.directorToolsPanel")
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .openChatIconButtonFrame(size: OpenChatDesignSystem.ControlSize.compactIconButton)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Collapse Director Tools"))
            .accessibilityIdentifier("chat.directorToolsCollapse")
        }
    }

    private var inputModePicker: some View {
        Picker(String(localized: "Input Mode"), selection: $inputRole) {
            Label(String(localized: "Participant"), systemImage: "bubble.left.and.bubble.right")
                .accessibilityIdentifier("chat.stageInputMode.participant")
                .tag(StageInputRole.participant)
            Label(String(localized: "Director"), systemImage: "megaphone")
                .accessibilityIdentifier("chat.stageInputMode.director")
                .tag(StageInputRole.director)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("chat.stageInputModePicker")
    }

    @ViewBuilder
    private var content: some View {
        if inputRole.isDirectorInstructionInput {
            directorHint
        } else if activeParticipants.isEmpty {
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

    private var directorHint: some View {
        Label(
            String(localized: "Director input is saved as a hidden stage instruction."),
            systemImage: "eye.slash"
        )
        .font(OpenChatDesignSystem.Typography.metadata)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
        .accessibilityIdentifier("chat.directorInstructionHint")
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

            reorderButton(participant, index: index, offset: -1)
            reorderButton(participant, index: index, offset: 1)
        }
        .padding(.vertical, 2)
    }

    private func reorderButton(_ participant: StageParticipantRecord, index: Int?, offset: Int) -> some View {
        let isDown = offset > 0
        return Button {
            moveResponder(participant, offset: offset)
        } label: {
            Image(systemName: isDown ? "chevron.down" : "chevron.up")
                .openChatIconButtonFrame(size: OpenChatDesignSystem.ControlSize.compactIconButton)
        }
        .buttonStyle(.plain)
        .disabled(index == nil || index == disabledBoundary(forDown: isDown))
        .accessibilityLabel(isDown ? String(localized: "Move responder down") : String(localized: "Move responder up"))
        .accessibilityIdentifier("chat.directorResponder\(isDown ? "Down" : "Up").\(participant.displayName)")
    }

    private func disabledBoundary(forDown isDown: Bool) -> Int {
        isDown ? responderIds.count - 1 : 0
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
}
