import Foundation

enum PromptSegment {
    case systemPrompt(String)
    case worldBookEntry(WorldBookEntryRecord)
    case characterDescription(String)
    case scenario(String)
    case exampleDialog(ChatMessage)
    case historyMessage(MessageRecord)
    case currentInput(String)

    var role: String {
        switch self {
        case .exampleDialog(let message):
            message.role
        case .historyMessage(let message):
            message.role
        case .currentInput:
            "user"
        default:
            "system"
        }
    }

    var content: String {
        switch self {
        case .systemPrompt(let value), .characterDescription(let value), .scenario(let value), .currentInput(let value):
            value
        case .worldBookEntry(let entry):
            entry.content
        case .exampleDialog(let message):
            message.content
        case .historyMessage(let message):
            message.content
        }
    }

    var tokenCount: Int {
        TokenCounter.count(content)
    }

    var priority: Int {
        switch self {
        case .systemPrompt, .characterDescription, .scenario, .currentInput:
            .max
        case .worldBookEntry(let entry):
            entry.priority
        case .exampleDialog:
            75
        case .historyMessage:
            50
        }
    }

    var isRequired: Bool {
        switch self {
        case .systemPrompt, .currentInput:
            true
        default:
            false
        }
    }
}
