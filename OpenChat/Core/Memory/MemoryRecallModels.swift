import Foundation

struct MemoryRecallResult: Sendable {
    let entries: [MemoryRecallEntry]
    let trace: MemoryRecallTrace
}

struct MemoryRecallEntry: Sendable {
    let memory: MemoryEntryRecord
    let finalRank: Int
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordRank: Int?
    let recencyRank: Int?
    let reasons: [MemoryRecallReason]
}

struct MemoryRecallTrace: Sendable {
    let query: String
    let semanticCandidateCount: Int
    let keywordCandidateCount: Int
    let recentCandidateCount: Int
    let selectedIds: [String]
    let omitted: [MemoryRecallOmission]
    let fallback: MemoryRecallFallback?
}

enum MemoryRecallReason: String, Sendable {
    case semantic
    case keyword
    case recentHighValue
}

enum MemoryRecallFallback: String, Sendable {
    case semanticUnavailable
    case noSemanticHit
    case emptyIndex
}

struct MemoryRecallOmission: Sendable {
    let memoryId: String
    let reason: MemoryRecallOmissionReason
}

enum MemoryRecallOmissionReason: String, Sendable {
    case distanceThreshold
    case duplicate
    case limitExceeded
}
