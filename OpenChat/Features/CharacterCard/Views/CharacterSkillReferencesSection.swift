import SwiftUI

struct CharacterSkillReferencesSection: View {
    let referenceDrafts: [CharacterSkillReferenceDraft]
    let textBinding: (CharacterSkillReferenceDraft) -> Binding<String>

    var body: some View {
        Section(String(localized: "References")) {
            if referenceDrafts.isEmpty {
                Text(String(localized: "No reference markdown files."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(referenceDrafts) { draft in
                    CharacterSkillReferenceDraftRow(
                        draft: draft,
                        markdown: textBinding(draft)
                    )
                }
            }
        }
    }
}
