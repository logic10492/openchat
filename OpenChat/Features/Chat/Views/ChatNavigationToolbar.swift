import SwiftUI

struct ChatNavigationToolbar: ToolbarContent {
    let viewModel: ChatViewModel
    @Binding var isShowingSettings: Bool
    @Binding var isShowingCharacterPicker: Bool
    @Binding var selectedCharacterPickerWorldBookID: String?

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            characterCapsuleControl
                .offset(y: 3)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.isGeneratingTitle {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel(String(localized: "Chat Settings"))
            .accessibilityIdentifier("chat.settingsButton")
        }
    }

    @ViewBuilder
    private var characterCapsuleControl: some View {
        if viewModel.showsConversationCharacterPicker {
            Button {
                presentCharacterPicker()
            } label: {
                ChatHeaderCapsule(
                    title: viewModel.selectedCharacterName ?? String(localized: "Select Character"),
                    subtitle: viewModel.selectedCharacterWorldBookName
                )
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isShowingCharacterPicker,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                CharacterPickerPopover(
                    worldBooks: viewModel.availableWorldBooks,
                    characterCards: viewModel.availableCharacterCards,
                    selectedCharacterCardID: viewModel.selectedCharacterCardID,
                    selectedWorldBookID: $selectedCharacterPickerWorldBookID,
                    onSelectCharacterCard: { id in
                        selectCharacterCard(id)
                        isShowingCharacterPicker = false
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(String(localized: "Select Character"))
            .accessibilityIdentifier("chat.characterCapsule")
        } else {
            Button {
                isShowingSettings = true
            } label: {
                ChatHeaderCapsule(
                    title: String(localized: "Stage"),
                    subtitle: stageCapsuleSubtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stage"))
            .accessibilityIdentifier("chat.stageCapsule")
        }
    }

    private var selectedCharacterWorldBookID: String? {
        guard let id = viewModel.selectedCharacterCardID,
              let card = viewModel.availableCharacterCards.first(where: { $0.id == id }),
              let worldBookId = card.worldBookId,
              viewModel.availableWorldBooks.contains(where: { $0.id == worldBookId })
        else { return nil }
        return worldBookId
    }

    private var stageCapsuleSubtitle: String? {
        let names = viewModel.activeStageParticipants.map(\.displayName)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    private func presentCharacterPicker() {
        selectedCharacterPickerWorldBookID = selectedCharacterWorldBookID
        isShowingCharacterPicker = true
    }

    private func selectCharacterCard(_ id: String?) {
        guard viewModel.showsConversationCharacterPicker,
              viewModel.selectedCharacterCardID != id
        else { return }
        viewModel.selectedCharacterCardID = id
        Task { await viewModel.saveConversationSettings() }
    }
}
