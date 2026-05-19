import Foundation

enum DirectorMode: String, Codable, Sendable, CaseIterable {
    case silent
    case agent
    case userControlled
}

enum StageInputRole: String, Codable, Sendable, CaseIterable {
    case participant
    case director

    var isDirectorInstructionInput: Bool {
        self == .director
    }
}
