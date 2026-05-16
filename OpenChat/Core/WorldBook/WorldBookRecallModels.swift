import Foundation

enum WorldBookEmbeddingStatus: String, Codable, Sendable {
    case indexed
    case needsRebuild = "needs_rebuild"
    case failed
}

struct WorldBookRecallResult: Sendable {
    let entries: [WorldBookRecallEntry]
    let trace: WorldBookRecallTrace
}

struct WorldBookRecallEntry: Sendable {
    let entry: WorldBookEntryRecord
    let finalRank: Int
    let keywordRank: Int?
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordHits: [String]
    let reasons: [WorldBookRecallReason]
}

enum WorldBookRecallReason: String, Sendable {
    case keyword
    case semantic
}

struct WorldBookRecallTrace: Sendable {
    let querySummary: String
    let keywordCandidateCount: Int
    let semanticCandidateCount: Int
    let selectedIds: [String]
    let omissions: [WorldBookRecallOmission]
}

struct WorldBookRecallOmission: Sendable {
    let entryId: String?
    let reason: WorldBookRecallOmissionReason
    let detail: String?
}

enum WorldBookRecallOmissionReason: String, Sendable {
    case disabled
    case duplicate
    case limitExceeded
    case semanticUnavailable
    case staleEmbedding
}
