import Foundation

struct CharacterSkillReferenceDraft: Identifiable, Sendable, Equatable {
    var relativePath: String
    var markdown: String

    var id: String { relativePath }
}
