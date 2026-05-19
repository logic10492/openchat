import Foundation

enum DirectorMode: String, Codable, Sendable, CaseIterable, Hashable {
    case silent
    case agent
    case userControlled
}

enum StageInputRole: String, Codable, Sendable, CaseIterable, Hashable {
    case participant
    case director

    var isDirectorInstructionInput: Bool {
        self == .director
    }
}
