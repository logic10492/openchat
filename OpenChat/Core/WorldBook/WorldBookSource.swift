import Foundation

struct WorldBookSource: Sendable {
    private let embeddingProvider: any EmbeddingProvider
    private let vectorStore: WorldBookVectorStore

    init(
        embeddingProvider: any EmbeddingProvider,
        vectorStore: WorldBookVectorStore
    ) {
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
    }

    func recallEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String,
        limit: Int
    ) async throws -> WorldBookRecallResult {
        let keywordContextText = makeKeywordContextText(recentMessages: recentMessages, currentInput: currentInput)
        let queryText = makeSemanticQueryText(recentMessages: recentMessages, currentInput: currentInput)
        var omissions: [WorldBookRecallOmission] = []
        let normalizedLimit = max(limit, 0)

        guard let worldBook, worldBook.isEnabled, normalizedLimit > 0 else {
            let disabledOmissions = entries.map {
                WorldBookRecallOmission(entryId: $0.id, reason: .disabled, detail: nil)
            }
            return WorldBookRecallResult(
                entries: [],
                trace: WorldBookRecallTrace(
                    querySummary: summarize(queryText),
                    keywordCandidateCount: 0,
                    semanticCandidateCount: 0,
                    selectedIds: [],
                    omissions: disabledOmissions
                )
            )
        }

        let enabledEntries = entries.filter { entry in
            if entry.isEnabled {
                return true
            }
            omissions.append(WorldBookRecallOmission(entryId: entry.id, reason: .disabled, detail: nil))
            return false
        }

        let keywordCandidates = makeKeywordCandidates(entries: enabledEntries, contextText: keywordContextText)
        let semanticCandidates: [SemanticCandidate]
        do {
            let embedding = try embeddingProvider.embed(queryText, isQuery: true)
            semanticCandidates = try await vectorStore.search(
                query: embedding,
                worldBookId: worldBook.id,
                limit: max(normalizedLimit * 2, normalizedLimit)
            ).enumerated().map { index, result in
                SemanticCandidate(
                    entryId: result.entryId,
                    rank: index + 1,
                    distance: result.distance
                )
            }
        } catch {
            semanticCandidates = []
            omissions.append(
                WorldBookRecallOmission(
                    entryId: nil,
                    reason: .semanticUnavailable,
                    detail: error.localizedDescription
                )
            )
        }

        let fused = fuseCandidates(
            enabledEntries: enabledEntries,
            keywordCandidates: keywordCandidates,
            semanticCandidates: semanticCandidates,
            omissions: &omissions
        )

        let selected = Array(fused.prefix(normalizedLimit))
        if fused.count > normalizedLimit {
            omissions.append(contentsOf: fused.dropFirst(normalizedLimit).map {
                WorldBookRecallOmission(entryId: $0.entry.id, reason: .limitExceeded, detail: nil)
            })
        }

        let ranked = selected.enumerated().map { index, candidate in
            WorldBookRecallEntry(
                entry: candidate.entry,
                finalRank: index + 1,
                keywordRank: candidate.keywordRank,
                semanticRank: candidate.semanticRank,
                semanticDistance: candidate.semanticDistance,
                keywordHits: candidate.keywordHits,
                reasons: candidate.reasons
            )
        }

        return WorldBookRecallResult(
            entries: ranked,
            trace: WorldBookRecallTrace(
                querySummary: summarize(queryText),
                keywordCandidateCount: keywordCandidates.count,
                semanticCandidateCount: semanticCandidates.count,
                selectedIds: ranked.map(\.entry.id),
                omissions: omissions
            )
        )
    }

    private func makeKeywordCandidates(
        entries: [WorldBookEntryRecord],
        contextText: String
    ) -> [KeywordCandidate] {
        KeywordMatcher.triggeredEntries(entries, contextText: contextText)
            .enumerated()
            .map { index, entry in
                KeywordCandidate(
                    entry: entry,
                    rank: index + 1,
                    hits: keywordHits(entry: entry, contextText: contextText)
                )
            }
    }

    private func fuseCandidates(
        enabledEntries: [WorldBookEntryRecord],
        keywordCandidates: [KeywordCandidate],
        semanticCandidates: [SemanticCandidate],
        omissions: inout [WorldBookRecallOmission]
    ) -> [FusedCandidate] {
        let entriesById = Dictionary(uniqueKeysWithValues: enabledEntries.map { ($0.id, $0) })
        var fusedById: [String: FusedCandidate] = [:]

        for candidate in keywordCandidates {
            fusedById[candidate.entry.id] = FusedCandidate(
                entry: candidate.entry,
                keywordRank: candidate.rank,
                semanticRank: nil,
                semanticDistance: nil,
                keywordHits: candidate.hits
            )
        }

        for candidate in semanticCandidates {
            guard let entry = entriesById[candidate.entryId] else {
                omissions.append(
                    WorldBookRecallOmission(
                        entryId: candidate.entryId,
                        reason: .staleEmbedding,
                        detail: nil
                    )
                )
                continue
            }

            if var existing = fusedById[candidate.entryId] {
                omissions.append(
                    WorldBookRecallOmission(
                        entryId: candidate.entryId,
                        reason: .duplicate,
                        detail: nil
                    )
                )
                existing.semanticRank = candidate.rank
                existing.semanticDistance = candidate.distance
                fusedById[candidate.entryId] = existing
            } else {
                fusedById[candidate.entryId] = FusedCandidate(
                    entry: entry,
                    keywordRank: nil,
                    semanticRank: candidate.rank,
                    semanticDistance: candidate.distance,
                    keywordHits: []
                )
            }
        }

        return fusedById.values.sorted(by: sortCandidates)
    }

    private func sortCandidates(_ lhs: FusedCandidate, _ rhs: FusedCandidate) -> Bool {
        let lhsGroup = rankGroup(lhs)
        let rhsGroup = rankGroup(rhs)
        if lhsGroup != rhsGroup {
            return lhsGroup < rhsGroup
        }

        switch lhsGroup {
        case 0:
            let lhsSemantic = lhs.semanticRank ?? Int.max
            let rhsSemantic = rhs.semanticRank ?? Int.max
            if lhsSemantic != rhsSemantic {
                return lhsSemantic < rhsSemantic
            }
            let lhsKeyword = lhs.keywordRank ?? Int.max
            let rhsKeyword = rhs.keywordRank ?? Int.max
            if lhsKeyword != rhsKeyword {
                return lhsKeyword < rhsKeyword
            }
        case 1:
            let lhsKeyword = lhs.keywordRank ?? Int.max
            let rhsKeyword = rhs.keywordRank ?? Int.max
            if lhsKeyword != rhsKeyword {
                return lhsKeyword < rhsKeyword
            }
        default:
            let lhsSemantic = lhs.semanticRank ?? Int.max
            let rhsSemantic = rhs.semanticRank ?? Int.max
            if lhsSemantic != rhsSemantic {
                return lhsSemantic < rhsSemantic
            }
        }

        if lhs.entry.priority != rhs.entry.priority {
            return lhs.entry.priority > rhs.entry.priority
        }
        if lhs.entry.updatedAt != rhs.entry.updatedAt {
            return lhs.entry.updatedAt > rhs.entry.updatedAt
        }
        return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
    }

    private func rankGroup(_ candidate: FusedCandidate) -> Int {
        if candidate.keywordRank != nil && candidate.semanticRank != nil {
            return 0
        }
        if candidate.keywordRank != nil {
            return 1
        }
        return 2
    }

    private func keywordHits(entry: WorldBookEntryRecord, contextText: String) -> [String] {
        guard let keywords = try? entry.keywordValues() else {
            return []
        }
        return keywords.filter { KeywordMatcher.matches(keyword: $0, in: contextText) }
    }

    private func makeKeywordContextText(recentMessages: [MessageRecord], currentInput: String) -> String {
        let recentText = recentMessages.suffix(5).map(\.content).joined(separator: "\n")
        return [recentText, currentInput].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func makeSemanticQueryText(recentMessages: [MessageRecord], currentInput: String) -> String {
        let recentText = recentMessages
            .suffix(5)
            .map(\.content)
            .joined(separator: "\n")
        return """
        Current input:
        \(currentInput)

        Recent context:
        \(recentText)
        """
    }

    private func summarize(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard collapsed.count > 160 else {
            return collapsed
        }
        return String(collapsed.prefix(160))
    }
}

private struct KeywordCandidate: Sendable {
    let entry: WorldBookEntryRecord
    let rank: Int
    let hits: [String]
}

private struct SemanticCandidate: Sendable {
    let entryId: String
    let rank: Int
    let distance: Float
}

private struct FusedCandidate: Sendable {
    let entry: WorldBookEntryRecord
    let keywordRank: Int?
    var semanticRank: Int?
    var semanticDistance: Float?
    let keywordHits: [String]

    var reasons: [WorldBookRecallReason] {
        var values: [WorldBookRecallReason] = []
        if keywordRank != nil {
            values.append(.keyword)
        }
        if semanticRank != nil {
            values.append(.semantic)
        }
        return values
    }
}
