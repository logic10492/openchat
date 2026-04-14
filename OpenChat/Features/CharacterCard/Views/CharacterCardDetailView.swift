import SwiftUI

struct CharacterCardDetailView: View {
    let card: CharacterCardRecord
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(card.name)
                        .font(.largeTitle.bold())
                    detailSection(String(localized: "Personality"), value: card.personality)
                    detailSection(String(localized: "Appearance"), value: card.appearance)
                    detailSection(String(localized: "Speech"), value: card.speechStyle)
                    detailSection(String(localized: "Backstory"), value: card.backstory)
                }
                .padding()
            }
            .navigationTitle(String(localized: "Character"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Edit"), action: onEdit)
                }
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ title: String, value: String?) -> some View {
        if let value = value?.nilIfBlank {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).openChatInlineSectionTitle()
                MarkdownTextView(text: value)
            }
        }
    }
}
