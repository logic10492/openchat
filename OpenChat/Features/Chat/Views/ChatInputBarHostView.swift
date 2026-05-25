import SwiftUI

struct ChatInputBarHostView: View {
    let viewModel: ChatViewModel

    var body: some View {
        InputBarView(
            text: binding(\.inputText),
            isPrefillModeEnabled: binding(\.isPrefillModeEnabled),
            inputRole: binding(\.stageInputRole),
            responderIds: binding(\.stageResponderIds),
            prefillNextRole: viewModel.prefillNextRole,
            stageParticipants: viewModel.stageParticipants,
            showsDirectorTools: viewModel.isStageEnabled,
            isGenerating: viewModel.isGenerating,
            onSend: {
                Task { await viewModel.sendMessage() }
            },
            onStop: {
                viewModel.stopGenerating()
            },
            onCustomizeResponders: {
                viewModel.markStageResponderSelectionCustomized()
            }
        )
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ChatViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}
