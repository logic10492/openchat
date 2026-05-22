import SwiftUI

struct ReasoningDisclosureView: View {
    let reasoning: String
    var isStreaming = false

    @State private var isExpanded = false

    private let previewCharacterLimit = 1400
    private let previewHeight: CGFloat = 136

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            previewContent
                .padding(.top, OpenChatDesignSystem.Spacing.xs)
        } label: {
            labelContent
        }
        .padding(OpenChatDesignSystem.Spacing.xs)
        .background(
            OpenChatDesignSystem.Surface.reasoningWash,
            in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.md, style: .continuous)
                .stroke(Color.purple.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var labelContent: some View {
        HStack(spacing: OpenChatDesignSystem.Spacing.xs) {
            Label {
                Text(String(localized: "Character Thinking"))
            } icon: {
                Image(systemName: "brain")
            }

            if isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }

            Spacer(minLength: OpenChatDesignSystem.Spacing.xs)
        }
        .font(OpenChatDesignSystem.Typography.badge)
        .foregroundStyle(.purple)
    }

    private var previewContent: some View {
        ScrollView {
            Text(previewReasoning)
                .font(.callout)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OpenChatDesignSystem.Spacing.xs)
        }
        .frame(height: previewHeight)
        .background(
            RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .contentShape(RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous))
        .accessibilityLabel(String(localized: "Character Thinking"))
    }

    private var previewReasoning: String {
        guard cleanReasoning.count > previewCharacterLimit else {
            return cleanReasoning
        }

        let suffix = cleanReasoning.suffix(previewCharacterLimit)
        return "...\n" + suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanReasoning: String {
        reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("Collapsed") {
    ReasoningDisclosureView(
        reasoning: """
        First, I need to infer the user's intent from the latest message. Then I should preserve the roleplay tone while avoiding overexplaining the internal plan. The final response should stay concise.
        """
    )
    .padding()
}

#Preview("Expanded") {
    ReasoningDisclosureView(
        reasoning: Array(repeating: "The character compares the latest cue with prior scene context, checks tone continuity, and decides how much uncertainty to reveal.", count: 24)
            .joined(separator: "\n\n"),
        isStreaming: true
    )
    .padding()
}
