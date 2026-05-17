import Foundation

struct BackgroundDiagnostics: Sendable, Equatable {
    let requestId: String
    let startedAt: Date
    let endedAt: Date?
    let elapsedMilliseconds: Double?
    let policyProfile: [String: String]
    let agentPolicySummary: [String: String]
    let sourceSummaries: [BackgroundSourceSummary]
    let inputCandidateCount: Int
    let selectedIds: [String]
    let omitted: [BackgroundOmission]
    let fallbacks: [String]
    let warnings: [String]
}

extension BackgroundDiagnostics {
    func adding(
        sourceSummaries additionalSourceSummaries: [BackgroundSourceSummary] = [],
        fallbacks additionalFallbacks: [String] = [],
        warnings additionalWarnings: [String] = []
    ) -> BackgroundDiagnostics {
        BackgroundDiagnostics(
            requestId: requestId,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedMilliseconds: elapsedMilliseconds,
            policyProfile: policyProfile,
            agentPolicySummary: agentPolicySummary,
            sourceSummaries: sourceSummaries + additionalSourceSummaries,
            inputCandidateCount: inputCandidateCount,
            selectedIds: selectedIds,
            omitted: omitted,
            fallbacks: fallbacks + additionalFallbacks,
            warnings: warnings + additionalWarnings
        )
    }
}

struct BackgroundSourceSummary: Sendable, Equatable {
    let sourceType: BackgroundSourceType
    let candidateCount: Int
    let selectedCount: Int
    let omittedCount: Int
    let fallback: String?
}
