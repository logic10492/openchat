import Foundation

enum PromptSegment {
    case systemPrompt(String)
    case worldBookEntry(WorldBookEntryRecord)
    case characterDescription(String)
    case scenario(String)
    case slowPlotDirective(String)
    case memoryEntry(MemoryEntryRecord)
    case exampleDialogsBlock(String)
    case historyMessage(MessageRecord)
    case currentTurn(String)

    var role: String {
        switch self {
        case .historyMessage(let message):
            message.role
        case .currentTurn:
            "user"
        default:
            "system"
        }
    }

    var content: String {
        switch self {
        case .systemPrompt(let value), .characterDescription(let value),
             .scenario(let value), .slowPlotDirective(let value), .exampleDialogsBlock(let value), .currentTurn(let value):
            value
        case .worldBookEntry(let entry):
            entry.content
        case .memoryEntry(let entry):
            entry.content
        case .historyMessage(let message):
            message.content
        }
    }

    var tokenCount: Int {
        TokenCounter.count(content)
    }

    var priority: Int {
        switch self {
        case .systemPrompt, .characterDescription, .scenario, .slowPlotDirective, .currentTurn:
            .max
        case .worldBookEntry(let entry):
            entry.priority
        case .memoryEntry:
            85
        case .exampleDialogsBlock:
            75
        case .historyMessage:
            50
        }
    }

    var isRequired: Bool {
        switch self {
        case .systemPrompt, .currentTurn:
            true
        default:
            false
        }
    }
}
