import Foundation

struct BackgroundPromptItem: Sendable, Equatable {
    let id: String
    let sourceType: BackgroundSourceType
    let title: String?
    let label: String
    let content: String
    let estimatedTokens: Int
}

struct BackgroundAssembler: Sendable {
    static func stateItems(from packet: BackgroundPacket) -> [BackgroundPromptItem] {
        packet.entries
            .filter { $0.sourceType == .characterState || $0.sourceType == .conversationState }
            .sorted(by: sortEntries)
            .map { entry in
                BackgroundPromptItem(
                    id: entry.sourceId,
                    sourceType: entry.sourceType,
                    title: entry.title,
                    label: entry.title?.nilIfBlank ?? entry.sourceType.rawValue,
                    content: entry.content,
                    estimatedTokens: entry.estimatedTokens
                )
            }
    }

    static func worldBookItems(from packet: BackgroundPacket) -> [BackgroundPromptItem] {
        packet.entries
            .filter { $0.sourceType == .worldBook }
            .sorted(by: sortEntries)
            .map { entry in
                BackgroundPromptItem(
                    id: entry.sourceId,
                    sourceType: entry.sourceType,
                    title: entry.title,
                    label: entry.title?.nilIfBlank ?? entry.sourceId,
                    content: entry.content,
                    estimatedTokens: entry.estimatedTokens
                )
            }
    }

    static func memoryItems(from packet: BackgroundPacket) -> [BackgroundPromptItem] {
        packet.entries
            .filter { $0.sourceType == .memory }
            .sorted(by: sortEntries)
            .map { entry in
                BackgroundPromptItem(
                    id: entry.sourceId,
                    sourceType: entry.sourceType,
                    title: entry.title,
                    label: entry.title?.nilIfBlank ?? entry.metadata["memoryType"]?.nilIfBlank ?? entry.sourceId,
                    content: entry.content,
                    estimatedTokens: entry.estimatedTokens
                )
            }
    }

    static func makeWorldBookMessageContent(_ item: BackgroundPromptItem) -> String {
        "[World Book: \(item.label)]\n\(item.content)"
    }

    static func makeMemoryMessageContent(_ item: BackgroundPromptItem) -> String {
        "[Memory — \(item.label)]\n\(item.content)"
    }

    static func makeStateMessageContent(_ item: BackgroundPromptItem) -> String {
        let label: String
        switch item.sourceType {
        case .characterState:
            label = "Character State"
        case .conversationState:
            label = "Conversation State"
        case .memory:
            label = "Memory"
        case .worldBook:
            label = "World Book"
        }
        return "[\(label): \(item.label)]\n\(item.content)"
    }

    private static func sortEntries(_ lhs: BackgroundEntry, _ rhs: BackgroundEntry) -> Bool {
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        return lhs.id < rhs.id
    }
}
