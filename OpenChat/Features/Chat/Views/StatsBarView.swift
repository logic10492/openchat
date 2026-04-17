import SwiftUI

struct StatsBarView: View {
    let stats: StreamingStats
    let showDetailed: Bool

    var body: some View {
        if showDetailed {
            detailedView
        } else if stats.isContextLow {
            contextWarningView
        }
    }

    private var detailedView: some View {
        HStack(spacing: 8) {
            Label(String(localized: "In: \(stats.inputTokens)"), systemImage: "arrow.up.circle")
            Label(String(localized: "Out: \(stats.outputTokens)"), systemImage: "arrow.down.circle")
            if stats.reasoningTokens > 0 {
                Label(String(localized: "Think: \(stats.reasoningTokens)"), systemImage: "brain")
            }
            Label(String(format: "%.1f t/s", stats.tokensPerSecond), systemImage: "gauge.with.needle")
            contextLabel
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var contextWarningView: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(String(localized: "Context: \(stats.contextRemainingFormatted)"))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var contextLabel: some View {
        HStack(spacing: 2) {
            Image(systemName: stats.isContextLow ? "exclamationmark.triangle.fill" : "chart.bar.fill")
                .foregroundStyle(stats.isContextLow ? .orange : .secondary)
            Text(String(localized: "Ctx: \(stats.contextRemainingFormatted)"))
        }
    }
}

#Preview("Detailed") {
    StatsBarView(
        stats: StreamingStats(
            inputTokens: 1234,
            outputTokens: 567,
            reasoningTokens: 128,
            tokensPerSecond: 12.3,
            contextRemainingPercent: 0.62,
            totalBudget: 4096
        ),
        showDetailed: true
    )
    .padding()
}

#Preview("Low Context Warning") {
    StatsBarView(
        stats: StreamingStats(
            inputTokens: 3500,
            outputTokens: 200,
            tokensPerSecond: 8.5,
            contextRemainingPercent: 0.15,
            totalBudget: 4096
        ),
        showDetailed: false
    )
    .padding()
}
