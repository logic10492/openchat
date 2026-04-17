import Foundation

enum PromptSegment {
    case systemPrompt(String)
    case worldBookEntry(WorldBookEntryRecord)
    case characterDescription(String)
    case scenario(String)
    case slowPlotDirective(String)
    case timeContext(String)
    case memoryEntry(MemoryEntryRecord)
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
        case .systemPrompt(let value), .characterDescription(let value),
             .scenario(let value), .slowPlotDirective(let value), .timeContext(let value), .currentInput(let value):
            value
        case .worldBookEntry(let entry):
            entry.content
        case .memoryEntry(let entry):
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
        case .systemPrompt, .characterDescription, .scenario, .slowPlotDirective, .timeContext, .currentInput:
            .max
        case .worldBookEntry(let entry):
            entry.priority
        case .memoryEntry:
            85
        case .exampleDialog:
            75
        case .historyMessage:
            50
        }
    }

    var isRequired: Bool {
        switch self {
        case .systemPrompt, .timeContext, .currentInput:
            true
        default:
            false
        }
    }
}
