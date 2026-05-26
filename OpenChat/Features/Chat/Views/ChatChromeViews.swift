import SwiftUI

struct ChatChromeAppearance {
    let glassTint: Color
    let fallbackFill: Color
    let primaryText: Color
    let secondaryText: Color
    let placeholderText: Color
    let stroke: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            glassTint = Color.black.opacity(0.38)
            fallbackFill = Color(.secondarySystemBackground).opacity(0.82)
            primaryText = Color.white.opacity(0.94)
            secondaryText = Color.white.opacity(0.66)
            placeholderText = Color.white.opacity(0.42)
            stroke = Color.white.opacity(0.16)
            shadow = Color.black.opacity(0.28)
        } else {
            glassTint = Color.white.opacity(0.46)
            fallbackFill = Color(.secondarySystemBackground).opacity(0.76)
            primaryText = Color.black.opacity(0.86)
            secondaryText = Color.black.opacity(0.54)
            placeholderText = Color.black.opacity(0.34)
            stroke = Color.white.opacity(0.38)
            shadow = Color.black.opacity(0.10)
        }
    }
}

struct ChatDateSeparator: View {
    let date: Date

    var body: some View {
        Text(date.openChatTimestamp())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
            .accessibilityIdentifier("chat.dateSeparator")
    }
}

struct ChatHeaderCapsule: View {
    let title: String
    let subtitle: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        capsuleContent
            .modifier(ChatHeaderGlassCapsuleStyle(appearance: appearance))
    }

    private var appearance: ChatChromeAppearance {
        ChatChromeAppearance(colorScheme: colorScheme)
    }

    private var capsuleContent: some View {
        HStack(spacing: OpenChatDesignSystem.Spacing.sm) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appearance.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OpenChatDesignSystem.Typography.badge)
                        .foregroundStyle(appearance.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private struct ChatHeaderGlassCapsuleStyle: ViewModifier {
    let appearance: ChatChromeAppearance

    func body(content: Content) -> some View {
        let capsule = Capsule()
        content
            .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .frame(minWidth: 156, maxWidth: 252, minHeight: 48)
            .background {
                headerBackground(capsule)
            }
            .overlay {
                capsule
                    .stroke(appearance.stroke, lineWidth: 0.7)
                    .blendMode(.overlay)
            }
            .shadow(color: appearance.shadow, radius: 10, x: 0, y: 4)
            .contentShape(capsule)
    }

    @ViewBuilder
    private func headerBackground(_ capsule: Capsule) -> some View {
        if #available(iOS 26.0, *) {
            capsule
                .fill(appearance.glassTint)
                .glassEffect(.regular.tint(appearance.glassTint).interactive(), in: capsule)
        } else {
            capsule.fill(appearance.fallbackFill)
        }
    }
}

struct CharacterPickerPopover: View {
    let worldBooks: [WorldBookRecord]
    let characterCards: [CharacterCardRecord]
    let selectedCharacterCardID: String?
    @Binding var selectedWorldBookID: String?
    let onSelectCharacterCard: (String?) -> Void

    private var filteredCharacterCards: [CharacterCardRecord] {
        characterCards.filter { card in
            if let selectedWorldBookID {
                return card.worldBookId == selectedWorldBookID
            }
            return card.worldBookId == nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.sm) {
            worldBookSection
            Divider()
            characterSection
        }
        .padding(OpenChatDesignSystem.Spacing.sm)
        .frame(width: 320, alignment: .leading)
    }

    private var worldBookSection: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
            sectionHeader(String(localized: "Available World Books"))

            VStack(spacing: OpenChatDesignSystem.Spacing.xxs) {
                pickerRow(
                    title: String(localized: "No World Book"),
                    systemImage: "book.closed",
                    isSelected: selectedWorldBookID == nil
                ) {
                    selectedWorldBookID = nil
                }

                ForEach(worldBooks) { book in
                    pickerRow(
                        title: book.name,
                        systemImage: book.isEnabled ? "book" : "book.closed",
                        isSelected: selectedWorldBookID == book.id
                    ) {
                        selectedWorldBookID = book.id
                    }
                }
            }
        }
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
            sectionHeader(String(localized: "World Book Characters"))

            VStack(spacing: OpenChatDesignSystem.Spacing.xxs) {
                pickerRow(
                    title: String(localized: "None"),
                    systemImage: "person.slash",
                    isSelected: selectedCharacterCardID == nil
                ) {
                    onSelectCharacterCard(nil)
                }

                if filteredCharacterCards.isEmpty {
                    Text(String(localized: "No Characters"))
                        .font(OpenChatDesignSystem.Typography.secondary)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
                        .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
                } else {
                    ForEach(filteredCharacterCards) { card in
                        pickerRow(
                            title: card.name,
                            systemImage: "person",
                            isSelected: selectedCharacterCardID == card.id
                        ) {
                            onSelectCharacterCard(card.id)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OpenChatDesignSystem.Typography.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
    }

    private func pickerRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OpenChatDesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: OpenChatDesignSystem.IconSize.md)

                Text(title)
                    .font(OpenChatDesignSystem.Typography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: OpenChatDesignSystem.Spacing.sm)

                Image(systemName: "checkmark")
                    .font(OpenChatDesignSystem.Typography.badge)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .background(
                isSelected ? OpenChatDesignSystem.Surface.accentWash : Color.clear,
                in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EditMessageSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(OpenChatDesignSystem.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(OpenChatDesignSystem.Spacing.md)
                .background(OpenChatDesignSystem.Surface.pageBackground)
                .navigationTitle(String(localized: "Edit Message"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel"), action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save"), action: onSave)
                            .disabled(!canSave)
                    }
                }
        }
    }
}
