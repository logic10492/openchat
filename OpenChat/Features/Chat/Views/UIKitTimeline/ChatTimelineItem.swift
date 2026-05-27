import Foundation

enum ChatTimelineItem: Hashable {
    case loadEarlier(hasMore: Bool, isLoading: Bool)
    case empty
    case dateSeparator(id: String, date: Date)
    case message(ChatTimelineMessageRow)
    case extraction(ChatTimelineExtractionItem)
    case diagnostics(String)
    case performanceCompletion

    var stableID: String {
        switch self {
        case .loadEarlier:
            "load-earlier"
        case .empty:
            "empty"
        case let .dateSeparator(id, _):
            id
        case let .message(row):
            row.item.id
        case .extraction:
            "extraction-indicator"
        case .diagnostics:
            "retrieval-trace"
        case .performanceCompletion:
            "performance-completion"
        }
    }
}

struct ChatTimelineMessageRow: Hashable {
    let item: MessageDisplayItem
    let isStreaming: Bool
    let showDetailedStats: Bool
    let canEdit: Bool
    let isGroupedWithPrevious: Bool
    let isGroupedWithNext: Bool
    let topPadding: Double
}

enum ChatTimelineItemBuilder {
    static func makeItems(
        messages: [MessageDisplayItem],
        isGenerating: Bool,
        showDetailedStats: Bool,
        extractionPhase: MemoryExtractionPhase,
        backgroundDiagnostics: BackgroundDiagnostics?,
        hasEarlierMessages: Bool,
        isLoadingEarlierMessages: Bool
    ) -> [ChatTimelineItem] {
        if messages.isEmpty && !isGenerating {
            return [.empty]
        }

        var items: [ChatTimelineItem] = []
        if hasEarlierMessages || isLoadingEarlierMessages {
            items.append(.loadEarlier(hasMore: hasEarlierMessages, isLoading: isLoadingEarlierMessages))
        }

        for index in messages.indices {
            let item = messages[index]
            if shouldShowDateSeparator(messages: messages, at: index) {
                items.append(.dateSeparator(id: "date-separator-\(item.id)", date: item.createdAt))
            }

            let isStreaming = isGenerating && item.id == messages.last?.id && item.role == "assistant"
            let groupedWithPrevious = isGroupedWithPrevious(messages: messages, at: index)
            items.append(
                .message(
                    ChatTimelineMessageRow(
                        item: item,
                        isStreaming: isStreaming,
                        showDetailedStats: showDetailedStats,
                        canEdit: !isGenerating,
                        isGroupedWithPrevious: groupedWithPrevious,
                        isGroupedWithNext: isGroupedWithNext(messages: messages, at: index),
                        topPadding: groupedWithPrevious ? 2 : 7
                    )
                )
            )
        }

        if extractionPhase.isActive {
            items.append(.extraction(ChatTimelineExtractionItem(phase: extractionPhase)))
        }

        if showDetailedStats, let backgroundDiagnostics {
            items.append(.diagnostics(makeDiagnosticsSummary(backgroundDiagnostics)))
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-chat-performance"),
           messages.last?.content.contains("Perf stream chunk 119") == true {
            items.append(.performanceCompletion)
        }
        #endif

        return items
    }

    private static func shouldShowDateSeparator(messages: [MessageDisplayItem], at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].createdAt, inSameDayAs: messages[index - 1].createdAt)
    }

    private static func isGroupedWithPrevious(messages: [MessageDisplayItem], at index: Int) -> Bool {
        guard messages.indices.contains(index), index > 0 else { return false }
        return shouldGroup(messages[index], with: messages[index - 1])
    }

    private static func isGroupedWithNext(messages: [MessageDisplayItem], at index: Int) -> Bool {
        guard messages.indices.contains(index), messages.indices.contains(index + 1) else { return false }
        return shouldGroup(messages[index], with: messages[index + 1])
    }

    private static func shouldGroup(_ lhs: MessageDisplayItem, with rhs: MessageDisplayItem) -> Bool {
        guard lhs.role == rhs.role,
              lhs.speakerId == rhs.speakerId,
              lhs.speakerName == rhs.speakerName,
              Calendar.current.isDate(lhs.createdAt, inSameDayAs: rhs.createdAt)
        else { return false }
        return abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) < 5 * 60
    }

    private static func makeDiagnosticsSummary(_ diagnostics: BackgroundDiagnostics) -> String {
        let summaries = diagnostics.sourceSummaries.map { summary in
            "\(summary.sourceType.rawValue): \(summary.selectedCount)/\(summary.candidateCount)"
        }
        guard !summaries.isEmpty else {
            return "Retrieval trace"
        }
        return summaries.joined(separator: "  ")
    }
}

struct ChatTimelineExtractionItem: Hashable {
    let state: State
    let count: Int?
    let summaries: [String]
    let description: String?

    init(phase: MemoryExtractionPhase) {
        switch phase {
        case .extracting:
            state = .extracting
            count = nil
            summaries = []
            description = nil
        case let .completed(count, summaries):
            state = .completed
            self.count = count
            self.summaries = summaries
            description = nil
        case let .failed(description):
            state = .failed
            count = nil
            summaries = []
            self.description = description
        case .idle, .skipped:
            state = .idle
            count = nil
            summaries = []
            description = nil
        }
    }

    enum State: Hashable {
        case idle
        case extracting
        case completed
        case failed
    }
}
