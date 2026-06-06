import SwiftUI

struct CharacterSkillReferenceDraftRow: View {
    let draft: CharacterSkillReferenceDraft
    @Binding var markdown: String

    var body: some View {
        DisclosureGroup {
            TextField(
                String(localized: "Reference markdown"),
                text: $markdown,
                axis: .vertical
            )
            .font(.body.monospaced())
            .lineLimit(8...)
        } label: {
            Label(draft.relativePath, systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
        }
    }
}
