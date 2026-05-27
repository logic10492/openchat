import SwiftUI
import UIKit

struct ChatTimelineUIKitRepresentable: UIViewControllerRepresentable {
    let configuration: ChatTimelineConfiguration

    func makeUIViewController(context: Context) -> ChatTimelineViewController {
        ChatTimelineViewController(configuration: configuration)
    }

    func updateUIViewController(_ viewController: ChatTimelineViewController, context: Context) {
        viewController.update(configuration)
    }
}

struct ChatTimelineConfiguration {
    let messages: [MessageDisplayItem]
    let isGenerating: Bool
    let showDetailedStats: Bool
    let extractionPhase: MemoryExtractionPhase
    let backgroundDiagnostics: BackgroundDiagnostics?
    let hasEarlierMessages: Bool
    let isLoadingEarlierMessages: Bool
    let onLoadEarlier: () -> Void
    let onEdit: (MessageDisplayItem) -> Void
    let onDelete: (String) -> Void
    let onRegenerate: () -> Void
    let onDismissExtraction: () -> Void
    let onScrollingChanged: (Bool) -> Void

    var lastMessageID: String? {
        messages.last?.id
    }

    var latestStreamingRevision: Int {
        guard isGenerating, let last = messages.last, last.role == "assistant" else {
            return -1
        }
        return last.streamingRenderRevision
    }
}
