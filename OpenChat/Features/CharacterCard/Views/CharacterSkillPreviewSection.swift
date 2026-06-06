import SwiftUI

struct CharacterSkillPreviewSection: View {
    let previewText: String

    var body: some View {
        Section(String(localized: "Prompt Preview")) {
            DisclosureGroup(String(localized: "Role Skill Block")) {
                Text(previewText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}
