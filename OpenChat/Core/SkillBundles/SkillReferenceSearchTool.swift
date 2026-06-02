import Foundation

struct SkillReferenceSearchToolInput: Equatable, Sendable {
    let characterCardId: String
    let query: String
    let limit: Int
}

struct SkillReferenceSearchResult: Equatable, Sendable {
    let entries: [SkillReferenceSearchEntry]
    let trace: SkillReferenceSearchTrace
}

struct SkillReferenceSearchEntry: Equatable, Sendable {
    let id: String
    let bundleId: String
    let characterCardId: String
    let relativePath: String
    let title: String
    let excerpt: String
    let score: Double
    let matchedTerms: [String]
    let finalRank: Int
}

struct SkillReferenceSearchTrace: Equatable, Sendable {
    let query: String
    let candidateFileCount: Int
    let selectedIds: [String]
    let omitted: [SkillReferenceSearchOmission]
    let fallback: String?
}

struct SkillReferenceSearchOmission: Equatable, Sendable {
    let relativePath: String
    let reason: String
}

struct SkillReferenceSearchTool: BackgroundSourceTool {
    let sourceType: BackgroundSourceType = .skillReference
    let databaseManager: DatabaseManager
    let store: CharacterSkillBundleStore
    let maxFileBytes: Int
    let maxExcerptCharacters: Int

    init(
        databaseManager: DatabaseManager,
        store: CharacterSkillBundleStore,
        maxFileBytes: Int = 96_000,
        maxExcerptCharacters: Int = 700
    ) {
        self.databaseManager = databaseManager
        self.store = store
        self.maxFileBytes = max(maxFileBytes, 1)
        self.maxExcerptCharacters = max(maxExcerptCharacters, 120)
    }

    func call(_ input: SkillReferenceSearchToolInput) async throws -> SkillReferenceSearchResult {
        let queryTerms = Self.queryTerms(from: input.query)
        guard !queryTerms.isEmpty,
              let record = try await databaseManager.fetchCharacterSkillBundle(characterCardId: input.characterCardId)
        else {
            return SkillReferenceSearchResult(
                entries: [],
                trace: SkillReferenceSearchTrace(
                    query: input.query,
                    candidateFileCount: 0,
                    selectedIds: [],
                    omitted: [],
                    fallback: "noBundleOrQuery"
                )
            )
        }

        let files = try store.referenceMarkdownFiles(for: record)
        var scored: [ScoredSkillReference] = []
        var omitted: [SkillReferenceSearchOmission] = []

        for file in files {
            let markdown = try store.readReferenceMarkdown(for: record, relativePath: file.relativePath)
            guard markdown.utf8.count <= maxFileBytes else {
                omitted.append(
                    SkillReferenceSearchOmission(
                        relativePath: file.relativePath,
                        reason: "fileTooLarge"
                    )
                )
                continue
            }

            let match = Self.match(
                content: markdown,
                relativePath: file.relativePath,
                queryTerms: queryTerms,
                maxExcerptCharacters: maxExcerptCharacters
            )
            guard match.score > 0 else {
                omitted.append(
                    SkillReferenceSearchOmission(
                        relativePath: file.relativePath,
                        reason: "noMatch"
                    )
                )
                continue
            }

            scored.append(
                ScoredSkillReference(
                    relativePath: file.relativePath,
                    title: match.title,
                    excerpt: match.excerpt,
                    score: match.score,
                    matchedTerms: match.matchedTerms
                )
            )
        }

        let selected = scored
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.relativePath < $1.relativePath
            }
            .prefix(max(input.limit, 0))
            .enumerated()
            .map { index, item in
                SkillReferenceSearchEntry(
                    id: "skillReference:\(record.id):\(item.relativePath)",
                    bundleId: record.id,
                    characterCardId: input.characterCardId,
                    relativePath: item.relativePath,
                    title: item.title,
                    excerpt: item.excerpt,
                    score: item.score,
                    matchedTerms: item.matchedTerms,
                    finalRank: index + 1
                )
            }

        return SkillReferenceSearchResult(
            entries: Array(selected),
            trace: SkillReferenceSearchTrace(
                query: input.query,
                candidateFileCount: files.count,
                selectedIds: selected.map(\.id),
                omitted: omitted,
                fallback: files.isEmpty ? "noReferences" : nil
            )
        )
    }

    private static func match(
        content: String,
        relativePath: String,
        queryTerms: [String],
        maxExcerptCharacters: Int
    ) -> SkillReferenceMatch {
        let title = title(from: content, relativePath: relativePath)
        let haystack = "\(relativePath)\n\(title)\n\(content)".lowercased()
        var score = 0.0
        var matchedTerms: [String] = []

        for term in queryTerms {
            let occurrences = haystack.components(separatedBy: term).count - 1
            guard occurrences > 0 else { continue }
            matchedTerms.append(term)
            score += min(Double(occurrences), 6)
            if relativePath.lowercased().contains(term) {
                score += 2
            }
            if title.lowercased().contains(term) {
                score += 2
            }
        }

        return SkillReferenceMatch(
            title: title,
            excerpt: excerpt(from: content, terms: matchedTerms, maxCharacters: maxExcerptCharacters),
            score: score,
            matchedTerms: matchedTerms
        )
    }

    private static func queryTerms(from query: String) -> [String] {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var terms: [String] = []
        for token in normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let term = String(token)
            if term.count >= 2 {
                terms.append(term)
            }
        }
        if normalized.count >= 2, normalized.count <= 48 {
            terms.append(normalized)
        }
        return uniqueOrdered(terms)
    }

    private static func title(from content: String, relativePath: String) -> String {
        if let heading = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) {
            let title = heading
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            if !title.isEmpty {
                return title
            }
        }
        return URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
    }

    private static func excerpt(from content: String, terms: [String], maxCharacters: Int) -> String {
        guard let term = terms.first,
              let range = content.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return String(content.prefix(maxCharacters))
        }

        let context = max(maxCharacters / 2, 80)
        let start = content.index(range.lowerBound, offsetBy: -context, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: context, limitedBy: content.endIndex) ?? content.endIndex
        var excerpt = String(content[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if start > content.startIndex {
            excerpt = "..." + excerpt
        }
        if end < content.endIndex {
            excerpt += "..."
        }
        return excerpt
    }

    private static func uniqueOrdered(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct SkillReferenceBackgroundSource: BackgroundSource {
    typealias Search = @Sendable (
        _ characterCardId: String,
        _ query: String,
        _ limit: Int
    ) async throws -> SkillReferenceSearchResult

    let sourceType: BackgroundSourceType = .skillReference

    private let search: Search

    init(search: @escaping Search) {
        self.search = search
    }

    init(tool: SkillReferenceSearchTool) {
        self.search = { characterCardId, query, limit in
            try await tool.call(
                SkillReferenceSearchToolInput(
                    characterCardId: characterCardId,
                    query: query,
                    limit: limit
                )
            )
        }
    }

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        let characterCardIds = Self.characterCardIds(for: request)
        guard !characterCardIds.isEmpty else { return [] }

        let query = Self.enrichedQuery(for: request)
        var candidates: [BackgroundCandidate] = []
        for characterCardId in characterCardIds {
            let result = try await search(
                characterCardId,
                query,
                max(request.skillReferenceLimit, 0)
            )
            candidates.append(contentsOf: Self.candidates(from: result, characterCardId: characterCardId))
        }
        return candidates
    }

    static func candidates(
        from result: SkillReferenceSearchResult,
        characterCardId: String? = nil
    ) -> [BackgroundCandidate] {
        result.entries.map { entry in
            BackgroundCandidate(
                id: entry.id,
                sourceType: .skillReference,
                sourceId: "\(entry.bundleId):\(entry.relativePath)",
                content: entry.excerpt,
                title: entry.title,
                basePriority: Int(min(max(entry.score * 10, 0), 100)),
                relevance: min(max(entry.score / 12, 0), 1),
                recency: nil,
                metadata: makeMetadata(entry: entry, trace: result.trace, characterCardId: characterCardId)
            )
        }
    }

    private static func makeMetadata(
        entry: SkillReferenceSearchEntry,
        trace: SkillReferenceSearchTrace,
        characterCardId: String?
    ) -> [String: String] {
        var metadata: [String: String] = [
            "sourceTable": CharacterSkillBundleRecord.databaseTableName,
            "sourceId": entry.bundleId,
            "characterCardId": characterCardId ?? entry.characterCardId,
            "relativePath": entry.relativePath,
            "finalRank": String(entry.finalRank),
            "score": String(entry.score),
            "matchedTerms": entry.matchedTerms.joined(separator: ","),
            "query": trace.query,
            "candidateFileCount": String(trace.candidateFileCount),
            "selectedIds": trace.selectedIds.joined(separator: ","),
            "omittedIds": trace.omitted.map(\.relativePath).joined(separator: ","),
            "omissionReasons": trace.omitted.map(\.reason).joined(separator: ","),
            "reasons": "skillReferenceSearch",
        ]
        metadata["fallback"] = trace.fallback
        return metadata
    }

    private static func characterCardIds(for request: BackgroundRequest) -> [String] {
        if let ids = request.stageContext?.activeCharacterCardIds, !ids.isEmpty {
            return ids
        }
        guard let id = request.characterCard?.id ?? request.conversation.characterCardId else {
            return []
        }
        return [id]
    }

    private static func enrichedQuery(for request: BackgroundRequest) -> String {
        guard let stageQuery = request.stageContext?.queryText,
              !stageQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return request.currentInput
        }
        return [request.currentInput, stageQuery]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

private struct ScoredSkillReference: Sendable {
    let relativePath: String
    let title: String
    let excerpt: String
    let score: Double
    let matchedTerms: [String]
}

private struct SkillReferenceMatch: Sendable {
    let title: String
    let excerpt: String
    let score: Double
    let matchedTerms: [String]
}
