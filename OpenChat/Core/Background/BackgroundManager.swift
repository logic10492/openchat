import Foundation

struct BackgroundManager: Sendable {
    typealias Prepare = @Sendable (
        _ request: BackgroundRequest,
        _ policy: BackgroundPolicy
    ) async throws -> BackgroundPacket

    private let sources: [any BackgroundSource]
    private let worker: BackgroundWorker
    private let prepareOverride: Prepare?

    init(
        sources: [any BackgroundSource],
        worker: BackgroundWorker = BackgroundWorker()
    ) {
        self.sources = sources
        self.worker = worker
        self.prepareOverride = nil
    }

    init(prepare: @escaping Prepare) {
        self.sources = []
        self.worker = BackgroundWorker()
        self.prepareOverride = prepare
    }

    func prepare(
        request: BackgroundRequest,
        policy: BackgroundPolicy
    ) async throws -> BackgroundPacket {
        if let prepareOverride {
            return try await prepareOverride(request, policy)
        }

        var candidates: [BackgroundCandidate] = []
        var sourceWarnings: [String] = []
        var sourceSummaries: [BackgroundSourceSummary] = []

        for source in sources {
            do {
                let sourceCandidates = try await source.candidates(for: request)
                candidates.append(contentsOf: sourceCandidates)
                sourceSummaries.append(
                    BackgroundSourceSummary(
                        sourceType: source.sourceType,
                        candidateCount: sourceCandidates.count,
                        selectedCount: 0,
                        omittedCount: 0,
                        fallback: sourceCandidates.compactMap { $0.metadata["fallback"] }.first
                    )
                )
            } catch {
                sourceWarnings.append("\(source.sourceType.rawValue) source failed: \(error.localizedDescription)")
                if source.sourceType == .worldBook {
                    candidates.append(contentsOf: makeWorldBookFallbackCandidates(for: request))
                }
                sourceSummaries.append(
                    BackgroundSourceSummary(
                        sourceType: source.sourceType,
                        candidateCount: 0,
                        selectedCount: 0,
                        omittedCount: 0,
                        fallback: "sourceError"
                    )
                )
            }
        }

        let packet = try await worker.run(
            BackgroundWorkerInput(
                request: request,
                candidates: candidates,
                policy: policy
            )
        )

        return packet.withDiagnostics(
            packet.diagnostics.adding(
                sourceSummaries: sourceSummaries,
                fallbacks: sourceWarnings.isEmpty ? [] : ["sourceError"],
                warnings: sourceWarnings
            )
        )
    }

    private func makeWorldBookFallbackCandidates(for request: BackgroundRequest) -> [BackgroundCandidate] {
        guard request.worldBook?.isEnabled ?? false else { return [] }
        let contextText = [
            request.recentMessages.suffix(5).map(\.content).joined(separator: "\n"),
            request.currentInput,
            request.stageContext?.queryText,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return KeywordMatcher.triggeredEntries(request.worldBookEntries, contextText: contextText).map { entry in
            BackgroundCandidate(
                id: "worldBook:\(entry.id)",
                sourceType: .worldBook,
                sourceId: entry.id,
                content: entry.content,
                title: entry.title,
                basePriority: entry.priority,
                relevance: nil,
                recency: entry.updatedAt,
                metadata: [
                    "sourceTable": WorldBookEntryRecord.databaseTableName,
                    "sourceId": entry.id,
                    "worldBookId": entry.worldBookId,
                    "priority": String(entry.priority),
                    "fallback": "sourceError",
                    "reasons": "keywordFallback",
                ]
            )
        }
    }
}
