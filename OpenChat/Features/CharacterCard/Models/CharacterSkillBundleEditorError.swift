import Foundation

enum CharacterSkillBundleEditorError: LocalizedError, Equatable {
    case missingBundle
    case missingSkillName
    case emptySkillMarkdown

    var errorDescription: String? {
        switch self {
        case .missingBundle:
            String(localized: "This character does not have an editable role skill bundle.")
        case .missingSkillName:
            String(localized: "SKILL.md frontmatter is missing required field: name.")
        case .emptySkillMarkdown:
            String(localized: "SKILL.md cannot be empty.")
        }
    }
}
