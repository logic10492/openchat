import Foundation

struct MessageDisplayItem: Identifiable, Hashable {
    let id: String
    var role: String
    var content: String
    var contentBlocks: [TextContentBlock]
    var contentRenderRevision: Int
    var reasoningContent: String?
    var reasoningRenderRevision: Int
    var tokenCount: Int?
    var isCompressed: Bool
    var originalContent: String?
    var createdAt: Date
    var sortOrder: Int
    var streamingStats: StreamingStats?
    var stageId: String?
    var speakerKind: MessageSpeakerKind?
    var speakerId: String?
    var speakerName: String?

    init(record: MessageRecord) {
        id = record.id
        role = record.role
        content = record.content
        contentBlocks = TextContentBlock.makeDisplayBlocks(from: record.content)
        contentRenderRevision = record.content.hashValue
        reasoningContent = record.reasoningContent
        reasoningRenderRevision = record.reasoningContent?.hashValue ?? 0
        tokenCount = record.tokenCount
        isCompressed = record.isCompressed
        originalContent = record.originalContent
        createdAt = record.createdAt
        sortOrder = record.sortOrder
        streamingStats = nil
        stageId = record.stageId
        speakerKind = record.speakerKindValue
        speakerId = record.speakerId
        speakerName = record.speakerName
    }

    mutating func appendContentDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        content += delta
        contentBlocks = TextContentBlock.appendingDisplay(delta, to: contentBlocks)
        contentRenderRevision &+= 1
    }

    mutating func appendReasoningContentDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        reasoningContent = (reasoningContent ?? "") + delta
        reasoningRenderRevision &+= 1
    }

    var streamingRenderRevision: Int {
        contentRenderRevision &+ reasoningRenderRevision
    }

    static func == (lhs: MessageDisplayItem, rhs: MessageDisplayItem) -> Bool {
        lhs.id == rhs.id
            && lhs.contentRenderRevision == rhs.contentRenderRevision
            && lhs.reasoningRenderRevision == rhs.reasoningRenderRevision
            && lhs.streamingStats == rhs.streamingStats
            && lhs.speakerName == rhs.speakerName
            && lhs.speakerKind == rhs.speakerKind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(contentRenderRevision)
        hasher.combine(reasoningRenderRevision)
        hasher.combine(speakerName)
        hasher.combine(speakerKind)
    }
}
