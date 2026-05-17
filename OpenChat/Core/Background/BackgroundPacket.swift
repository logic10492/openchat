import Foundation

struct BackgroundWorkerInput: Sendable {
    let request: BackgroundRequest
    let candidates: [BackgroundCandidate]
    let policy: BackgroundPolicy
    let agentPolicy: AgentPolicy

    init(
        request: BackgroundRequest,
        candidates: [BackgroundCandidate],
        policy: BackgroundPolicy,
        agentPolicy: AgentPolicy = .backgroundWorkerDefault()
    ) {
        self.request = request
        self.candidates = candidates
        self.policy = policy
        self.agentPolicy = agentPolicy
    }
}

struct BackgroundPacket: Sendable, Equatable {
    let entries: [BackgroundEntry]
    let omitted: [BackgroundOmission]
    let diagnostics: BackgroundDiagnostics
}

extension BackgroundPacket {
    func withDiagnostics(_ diagnostics: BackgroundDiagnostics) -> BackgroundPacket {
        BackgroundPacket(
            entries: entries,
            omitted: omitted,
            diagnostics: diagnostics
        )
    }
}

struct BackgroundEntry: Identifiable, Sendable, Equatable {
    let id: String
    let sourceType: BackgroundSourceType
    let sourceId: String
    let title: String?
    let content: String
    let rank: Int
    let score: Double
    let estimatedTokens: Int
    let reason: String?
    let metadata: [String: String]
}

struct BackgroundOmission: Identifiable, Sendable, Equatable {
    let id: String
    let candidateId: String
    let sourceType: BackgroundSourceType
    let reason: BackgroundOmissionReason
    let detail: String?
}

enum BackgroundOmissionReason: String, Sendable, Equatable, CaseIterable {
    case budgetExceeded
    case sourceLimitExceeded
    case duplicate
    case lowRelevance
    case lowConfidence
    case contradiction
    case policyDenied
}
