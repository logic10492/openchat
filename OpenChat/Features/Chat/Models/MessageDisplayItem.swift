import Foundation

struct MessageDisplayItem: Identifiable, Hashable {
    let id: String
    var role: String
    var content: String
    var tokenCount: Int?
    var isCompressed: Bool
    var originalContent: String?
    var createdAt: Date
    var sortOrder: Int

    init(record: MessageRecord) {
        id = record.id
        role = record.role
        content = record.content
        tokenCount = record.tokenCount
        isCompressed = record.isCompressed
        originalContent = record.originalContent
        createdAt = record.createdAt
        sortOrder = record.sortOrder
    }
}
