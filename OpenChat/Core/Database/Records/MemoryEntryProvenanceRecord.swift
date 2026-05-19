import Foundation
import GRDB

struct MemoryEntryProvenanceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "memory_entry_provenance"

    var memoryEntryId: String
    var sourceStartSortOrder: Int?
    var sourceEndSortOrder: Int?
    var sourceMessageIds: String?
    var extractionModel: String?
    var extractionPromptVersion: String
    var confidence: Double?
    var dedupeKey: String?
    var tags: String?
    var createdAt: Date
    var updatedAt: Date

    static let memoryEntry = belongsTo(
        MemoryEntryRecord.self,
        using: ForeignKey(["memoryEntryId"])
    )

    var decodedSourceMessageIds: [String] {
        RecordCoders.decode([String].self, from: sourceMessageIds) ?? []
    }

    var decodedTags: [String] {
        RecordCoders.decode([String].self, from: tags) ?? []
    }

    init(
        memoryEntryId: String,
        sourceStartSortOrder: Int? = nil,
        sourceEndSortOrder: Int? = nil,
        sourceMessageIds: [String]? = nil,
        extractionModel: String? = nil,
        extractionPromptVersion: String = "v1",
        confidence: Double? = nil,
        dedupeKey: String? = nil,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.memoryEntryId = memoryEntryId
        self.sourceStartSortOrder = sourceStartSortOrder
        self.sourceEndSortOrder = sourceEndSortOrder
        self.sourceMessageIds = sourceMessageIds.flatMap { RecordCoders.encode($0) }
        self.extractionModel = extractionModel
        self.extractionPromptVersion = extractionPromptVersion
        self.confidence = confidence
        self.dedupeKey = dedupeKey
        self.tags = tags.flatMap { RecordCoders.encode($0) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct MemoryEntryLinkRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    static let databaseTableName = "memory_entry_link"

    var id: String
    var fromMemoryEntryId: String
    var toMemoryEntryId: String
    var relation: String
    var createdAt: Date

    static let fromMemoryEntry = belongsTo(
        MemoryEntryRecord.self,
        using: ForeignKey(["fromMemoryEntryId"])
    )
    static let toMemoryEntry = belongsTo(
        MemoryEntryRecord.self,
        using: ForeignKey(["toMemoryEntryId"])
    )

    var relationValue: MemoryEntryLinkRelation? {
        MemoryEntryLinkRelation(rawValue: relation)
    }

    init(
        id: String = UUID().uuidString,
        fromMemoryEntryId: String,
        toMemoryEntryId: String,
        relation: MemoryEntryLinkRelation,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromMemoryEntryId = fromMemoryEntryId
        self.toMemoryEntryId = toMemoryEntryId
        self.relation = relation.rawValue
        self.createdAt = createdAt
    }

    init(
        id: String = UUID().uuidString,
        fromMemoryEntryId: String,
        toMemoryEntryId: String,
        relation: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromMemoryEntryId = fromMemoryEntryId
        self.toMemoryEntryId = toMemoryEntryId
        self.relation = relation
        self.createdAt = createdAt
    }
}
