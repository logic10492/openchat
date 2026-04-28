import Foundation

struct ChatMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
    var reasoningContent: String?

    init(role: String, content: String, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
    }

    func requestMessage(includeReasoningContent: Bool = false) -> ChatMessage {
        guard includeReasoningContent else {
            return ChatMessage(role: role, content: content)
        }
        return self
    }
}
