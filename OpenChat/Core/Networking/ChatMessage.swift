import Foundation

struct ChatMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
