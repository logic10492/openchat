import Foundation

struct MessageDisplayItem: Identifiable, Hashable {
    let id: String
    var role: String
    var content: String
    var reasoningContent: String?
    var tokenCount: Int?
    var isCompressed: Bool
    var originalContent: String?
    var createdAt: Date
    var sortOrder: Int
    var streamingStats: StreamingStats?

    init(record: MessageRecord) {
        id = record.id
        role = record.role
        content = record.content
        reasoningContent = record.reasoningContent
        tokenCount = record.tokenCount
        isCompressed = record.isCompressed
        originalContent = record.originalContent
        createdAt = record.createdAt
        sortOrder = record.sortOrder
        streamingStats = nil
    }

    /// Inline memory extraction marker (not persisted)
    static func memoryMarker(content: String, isError: Bool = false) -> MessageDisplayItem {
        MessageDisplayItem(
            id: "memory-\(UUID().uuidString)",
            role: isError ? "memory-error" : "memory",
            content: content,
            reasoningContent: nil,
            tokenCount: nil,
            isCompressed: false,
            originalContent: nil,
            createdAt: .now,
            sortOrder: Int.max,
            streamingStats: nil
        )
    }

    private init(
        id: String,
        role: String,
        content: String,
        reasoningContent: String?,
        tokenCount: Int?,
        isCompressed: Bool,
        originalContent: String?,
        createdAt: Date,
        sortOrder: Int,
        streamingStats: StreamingStats?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.tokenCount = tokenCount
        self.isCompressed = isCompressed
        self.originalContent = originalContent
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.streamingStats = streamingStats
    }

    static func == (lhs: MessageDisplayItem, rhs: MessageDisplayItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.reasoningContent == rhs.reasoningContent && lhs.streamingStats == rhs.streamingStats
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(content)
        hasher.combine(reasoningContent)
    }
}
