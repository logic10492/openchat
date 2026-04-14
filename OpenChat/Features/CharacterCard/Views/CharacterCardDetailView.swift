import SwiftUI

struct CharacterCardDetailView: View {
    let card: CharacterCardRecord
    let onEdit: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    detailSections
                }
                .padding()
            }
            .navigationTitle(String(localized: "Character"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Edit"), action: onEdit)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }

            Text(card.name)
                .font(.title2.bold())

            if !card.decodedTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.decodedTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Sections

    private var detailSections: some View {
        VStack(spacing: 0) {
            disclosureSection(String(localized: "Personality"), value: card.personality)
            disclosureSection(String(localized: "Appearance"), value: card.appearance)
            disclosureSection(String(localized: "Physique"), value: card.physique)
            disclosureSection(String(localized: "Speech Style"), value: card.speechStyle)
            disclosureSection(String(localized: "Backstory"), value: card.backstory)
            disclosureSection(String(localized: "System Prompt"), value: card.systemPrompt)
            disclosureSection(String(localized: "Scenario"), value: card.scenario)
        }
    }

    @ViewBuilder
    private func disclosureSection(_ title: String, value: String?) -> some View {
        if let value = value?.nilIfBlank {
            DisclosureGroup {
                MarkdownTextView(text: value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    CharacterCardDetailView(
        card: CharacterCardRecord(
            id: "1",
            name: "Luna",
            avatar: nil,
            personality: "Cheerful and adventurous. Always looking for the next quest.",
            appearance: "Silver hair, bright blue eyes.",
            physique: nil,
            speechStyle: "Speaks in a playful, informal tone.",
            backstory: "Born in the **Crystal Kingdom**, Luna was raised by the forest elves.",
            systemPrompt: nil,
            scenario: nil,
            exampleDialogs: nil,
            creatorNotes: nil,
            tags: "[\"fantasy\", \"elf\"]",
            createdAt: .now,
            updatedAt: .now
        ),
        onEdit: {}
    )
}
