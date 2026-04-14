import Foundation

enum CharacterCardField: String, CaseIterable, Identifiable {
    case name
    case personality
    case appearance
    case physique
    case speechStyle
    case backstory
    case systemPrompt
    case scenario
    case creatorNotes

    var id: String { rawValue }
}
