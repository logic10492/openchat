import Foundation

struct BackgroundWorker: Sendable {
    typealias Clock = @Sendable () -> Date

    private let clock: Clock
    private let requestIdProvider: @Sendable (BackgroundRequest) -> String

    init(
        clock: @escaping Clock = { Date() },
        requestIdProvider: @escaping @Sendable (BackgroundRequest) -> String = { request in request.conversation.id }
    ) {
        self.clock = clock
        self.requestIdProvider = requestIdProvider
    }

    func run(_ input: BackgroundWorkerInput) async throws -> BackgroundPacket {
        try validate(agentPolicy: input.agentPolicy)

        let startedAt = clock()
        let evaluated = input.candidates.enumerated().map { index, candidate in
            ScoredCandidate(
                candidate: candidate,
                inputIndex: index,
                score: score(candidate: candidate, policy: input.policy),
                estimatedTokens: estimateTokens(candidate.content)
            )
        }
        let sorted = evaluated.sorted(by: sort)
        let (entries, omitted) = select(from: sorted, policy: input.policy)
        let endedAt = clock()
        let diagnostics = makeDiagnostics(
            input: input,
            entries: entries,
            omitted: omitted,
            startedAt: startedAt,
            endedAt: endedAt
        )
        return BackgroundPacket(
            entries: entries,
            omitted: omitted,
            diagnostics: diagnostics
        )
    }

    private func validate(agentPolicy: AgentPolicy) throws {
        if !agentPolicy.allowedCapabilities.contains(.deterministic) {
            throw AgentError.capabilityDenied(
                agentId: "background-worker",
                capability: .deterministic
            )
        }
        for capability in agentPolicy.allowedCapabilities
            where capability != .deterministic && capability != .internalDiagnostics {
            throw AgentError.capabilityDenied(
                agentId: "background-worker",
                capability: capability
            )
        }
        if agentPolicy.toolUsePolicy.allowNetwork {
            throw AgentError.networkDenied(agentId: "background-worker")
        }
        if agentPolicy.sideEffectPolicy.allowDatabaseWrite {
            throw AgentError.databaseWriteDenied(agentId: "background-worker")
        }
    }

    private func select(
        from sorted: [ScoredCandidate],
        policy: BackgroundPolicy
    ) -> ([BackgroundEntry], [BackgroundOmission]) {
        var entries: [BackgroundEntry] = []
        var omitted: [BackgroundOmission] = []
        var usedTokens = 0
        var selectedBySource: [BackgroundSourceType: Int] = [:]
        var seenContent: [String: BackgroundEntry] = [:]

        for item in sorted {
            let candidate = item.candidate

            if item.score < policy.lowConfidenceThreshold {
                omitted.append(makeOmission(candidate, reason: .lowConfidence))
                continue
            }

            let contentKey = normalizedContent(candidate.content)
            if let existing = seenContent[contentKey] {
                omitted.append(
                    makeOmission(
                        candidate,
                        reason: .duplicate,
                        detail: "Duplicate of \(existing.id)."
                    )
                )
                continue
            }

            if entries.count >= policy.maxEntries {
                omitted.append(makeOmission(candidate, reason: .sourceLimitExceeded, detail: "Max entries reached."))
                continue
            }

            let sourceCount = selectedBySource[candidate.sourceType, default: 0]
            if sourceCount >= policy.limit(for: candidate.sourceType) {
                omitted.append(makeOmission(candidate, reason: .sourceLimitExceeded))
                continue
            }

            if usedTokens + item.estimatedTokens > policy.tokenBudget, !entries.isEmpty {
                omitted.append(makeOmission(candidate, reason: .budgetExceeded))
                continue
            }

            let entry = BackgroundEntry(
                id: candidate.id,
                sourceType: candidate.sourceType,
                sourceId: candidate.sourceId,
                title: candidate.title,
                content: candidate.content,
                rank: entries.count + 1,
                score: item.score,
                estimatedTokens: item.estimatedTokens,
                reason: candidate.metadata["reasons"],
                metadata: candidate.metadata
            )
            entries.append(entry)
            seenContent[contentKey] = entry
            selectedBySource[candidate.sourceType] = sourceCount + 1
            usedTokens += item.estimatedTokens
        }

        return (entries, omitted)
    }

    private func makeDiagnostics(
        input: BackgroundWorkerInput,
        entries: [BackgroundEntry],
        omitted: [BackgroundOmission],
        startedAt: Date,
        endedAt: Date
    ) -> BackgroundDiagnostics {
        let selectedBySource = Dictionary(grouping: entries, by: \.sourceType)
        let omittedBySource = Dictionary(grouping: omitted, by: \.sourceType)
        let candidatesBySource = Dictionary(grouping: input.candidates, by: \.sourceType)

        let summaries = BackgroundSourceType.allCasesForBackground.map { sourceType in
            let sourceCandidates = candidatesBySource[sourceType] ?? []
            return BackgroundSourceSummary(
                sourceType: sourceType,
                candidateCount: sourceCandidates.count,
                selectedCount: selectedBySource[sourceType]?.count ?? 0,
                omittedCount: omittedBySource[sourceType]?.count ?? 0,
                fallback: sourceCandidates.compactMap { $0.metadata["fallback"] }.first
            )
        }

        let fallbacks = input.candidates.compactMap { candidate in
            candidate.metadata["fallback"].map { "\(candidate.sourceType.rawValue):\($0)" }
        }

        return BackgroundDiagnostics(
            requestId: requestIdProvider(input.request),
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedMilliseconds: max(0, endedAt.timeIntervalSince(startedAt) * 1_000),
            policyProfile: input.policy.profile,
            agentPolicySummary: makeAgentPolicySummary(input.agentPolicy),
            sourceSummaries: summaries,
            inputCandidateCount: input.candidates.count,
            selectedIds: entries.map(\.id),
            omitted: omitted,
            fallbacks: fallbacks,
            warnings: []
        )
    }

    private func makeAgentPolicySummary(_ policy: AgentPolicy) -> [String: String] {
        [
            "capabilities": policy.allowedCapabilities
                .map(\.rawValue)
                .sorted()
                .joined(separator: ","),
            "allowNetwork": String(policy.toolUsePolicy.allowNetwork),
            "allowDatabaseRead": String(policy.sideEffectPolicy.allowDatabaseRead),
            "allowDatabaseWrite": String(policy.sideEffectPolicy.allowDatabaseWrite),
            "exposeDiagnosticsToUser": String(policy.visibilityPolicy.exposeDiagnosticsToUser),
        ]
    }

    private func score(
        candidate: BackgroundCandidate,
        policy: BackgroundPolicy
    ) -> Double {
        let relevance = candidate.relevance ?? fallbackRelevance(candidate)
        let priorityBoost = min(max(Double(candidate.basePriority), 0), 100) / 1_000
        let recencyBoost = recencyScore(candidate.recency) * 0.05
        let fallbackPenalty = candidate.metadata["fallback"] == nil ? 0 : 0.15
        return relevance
            + policy.weight(for: candidate.sourceType)
            + priorityBoost
            + recencyBoost
            - fallbackPenalty
    }

    private func fallbackRelevance(_ candidate: BackgroundCandidate) -> Double {
        if let semanticRank = intValue(candidate.metadata["semanticRank"]), semanticRank > 0 {
            return 1 / Double(semanticRank)
        }
        if let keywordRank = intValue(candidate.metadata["keywordRank"]), keywordRank > 0 {
            return 0.6 / Double(keywordRank)
        }
        if let finalRank = intValue(candidate.metadata["finalRank"]), finalRank > 0 {
            return 0.4 / Double(finalRank)
        }
        return 0.1
    }

    private func recencyScore(_ date: Date?) -> Double {
        guard let date else { return 0 }
        return max(0, min(date.timeIntervalSince1970 / 1_000_000_000, 1))
    }

    private func sort(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        let lhsSourceRank = sourceRank(lhs.candidate.sourceType)
        let rhsSourceRank = sourceRank(rhs.candidate.sourceType)
        if lhsSourceRank != rhsSourceRank {
            return lhsSourceRank < rhsSourceRank
        }
        if lhs.inputIndex != rhs.inputIndex {
            return lhs.inputIndex < rhs.inputIndex
        }
        return lhs.candidate.id < rhs.candidate.id
    }

    private func sourceRank(_ sourceType: BackgroundSourceType) -> Int {
        switch sourceType {
        case .worldBook:
            return 0
        case .memory:
            return 1
        }
    }

    private func makeOmission(
        _ candidate: BackgroundCandidate,
        reason: BackgroundOmissionReason,
        detail: String? = nil
    ) -> BackgroundOmission {
        BackgroundOmission(
            id: "\(candidate.id):\(reason.rawValue)",
            candidateId: candidate.id,
            sourceType: candidate.sourceType,
            reason: reason,
            detail: detail
        )
    }

    private func estimateTokens(_ content: String) -> Int {
        max(TokenCounter.count(content), 1)
    }

    private func normalizedContent(_ content: String) -> String {
        content
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func intValue(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value)
    }
}

private struct ScoredCandidate: Sendable {
    let candidate: BackgroundCandidate
    let inputIndex: Int
    let score: Double
    let estimatedTokens: Int
}

private extension BackgroundSourceType {
    static var allCasesForBackground: [BackgroundSourceType] {
        [.worldBook, .memory]
    }
}
