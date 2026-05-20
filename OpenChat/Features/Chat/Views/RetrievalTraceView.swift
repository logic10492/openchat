import SwiftUI

struct RetrievalTraceView: View {
    let diagnostics: BackgroundDiagnostics

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                summaryGrid
                if !diagnostics.sourceSummaries.isEmpty {
                    sourceSummaryList
                }
                if !diagnostics.selectedIds.isEmpty {
                    labeledLine("Selected", diagnostics.selectedIds.joined(separator: ", "))
                }
                if !diagnostics.omitted.isEmpty {
                    labeledLine(
                        "Omitted",
                        diagnostics.omitted
                            .prefix(6)
                            .map { "\($0.candidateId): \($0.reason.rawValue)" }
                            .joined(separator: "\n")
                    )
                }
                if !diagnostics.fallbacks.isEmpty {
                    labeledLine("Fallbacks", diagnostics.fallbacks.joined(separator: ", "))
                }
                if !diagnostics.warnings.isEmpty {
                    labeledLine("Warnings", diagnostics.warnings.joined(separator: "\n"))
                }
            }
            .padding(.top, 6)
        } label: {
            Label(String(localized: "Retrieval Trace"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("chat.retrievalTrace")
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(String(localized: "Candidates"))
                Text("\(diagnostics.inputCandidateCount)")
                    .monospacedDigit()
            }
            GridRow {
                Text(String(localized: "Selected"))
                Text("\(diagnostics.selectedIds.count)")
                    .monospacedDigit()
            }
            GridRow {
                Text(String(localized: "Omitted"))
                Text("\(diagnostics.omitted.count)")
                    .monospacedDigit()
            }
        }
    }

    private var sourceSummaryList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Sources"))
                .font(.caption.weight(.semibold))
            ForEach(diagnostics.sourceSummaries, id: \.sourceType) { summary in
                Text("\(summary.sourceType.displayName): \(summary.candidateCount) candidates, \(summary.selectedCount) selected, \(summary.omittedCount) omitted")
                    .monospacedDigit()
            }
        }
    }

    private func labeledLine(_ label: LocalizedStringResource, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: label))
                .font(.caption.weight(.semibold))
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private extension BackgroundSourceType {
    var displayName: String {
        switch self {
        case .characterState:
            String(localized: "Character State")
        case .conversationState:
            String(localized: "Conversation State")
        case .worldBook:
            String(localized: "World Book")
        case .memory:
            String(localized: "Memory")
        }
    }
}

#Preview {
    RetrievalTraceView(
        diagnostics: BackgroundDiagnostics(
            requestId: "preview",
            startedAt: .now,
            endedAt: .now,
            elapsedMilliseconds: 1,
            policyProfile: [:],
            agentPolicySummary: [:],
            sourceSummaries: [
                BackgroundSourceSummary(sourceType: .characterState, candidateCount: 1, selectedCount: 1, omittedCount: 0, fallback: nil),
                BackgroundSourceSummary(sourceType: .memory, candidateCount: 2, selectedCount: 1, omittedCount: 1, fallback: nil),
            ],
            inputCandidateCount: 3,
            selectedIds: ["characterState:mara", "memory:1"],
            omitted: [],
            fallbacks: [],
            warnings: []
        )
    )
    .padding()
}
