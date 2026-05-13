import SwiftUI

struct MemoryExtractionIndicator: View {
    let phase: MemoryExtractionPhase
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        switch phase {
        case .idle, .skipped:
            EmptyView()

        case .extracting:
            extractingView

        case .completed(let count, let summaries):
            completedView(count: count, summaries: summaries)

        case .failed(let description):
            failedView(description: description)
        }
    }

    // MARK: - Extracting

    private var extractingView: some View {
        HStack(spacing: 6) {
            Text("🧠")
                .symbolEffect(.pulse)
            Text(String(localized: "Extracting memories…"))
        }
        .font(.caption.italic())
        .foregroundStyle(.secondary.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    // MARK: - Completed

    private func completedView(count: Int, summaries: [String]) -> some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("🧠")
                    Text(String(localized: "Memorized \(count) entries"))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.caption.italic())
                .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summaries, id: \.self) { summary in
                        Text("· \(summary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .seconds(3))
            onDismiss()
        }
    }

    // MARK: - Failed

    private func failedView(description: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("⚠️")
                Text(String(localized: "Memory extraction failed"))
            }
            .font(.caption.italic())
            .foregroundStyle(.red.opacity(0.7))

            Text(description)
                .font(.caption2)
                .foregroundStyle(.red.opacity(0.5))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 32)
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}
