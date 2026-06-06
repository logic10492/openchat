import SwiftUI

struct CharacterSkillSummarySection: View {
    let skillName: String
    let skillDescription: String
    let referenceCount: Int

    var body: some View {
        Section(String(localized: "Role Skill")) {
            LabeledContent(String(localized: "Name"), value: skillName)
            if let description = skillDescription.nilIfBlank {
                LabeledContent(String(localized: "Description"), value: description)
            }
            LabeledContent(String(localized: "References"), value: "\(referenceCount)")
        }
    }
}
