import SwiftUI

struct ChatTimelineHostView: View {
    let viewModel: ChatViewModel
    let onEdit: (MessageDisplayItem) -> Void

    var body: some View {
        ChatMessageTimelineView(
            messages: viewModel.messages,
            isGenerating: viewModel.isGenerating,
            showDetailedStats: viewModel.showDetailedStats,
            extractionPhase: viewModel.extractionPhase,
            backgroundDiagnostics: viewModel.backgroundDiagnostics,
            onEdit: onEdit,
            onDelete: { id in
                Task { await viewModel.deleteMessage(id) }
            },
            onRegenerate: {
                Task { await viewModel.regenerateLastResponse() }
            },
            onDismissExtraction: {
                viewModel.dismissExtractionIndicator()
            }
        )
    }
}
