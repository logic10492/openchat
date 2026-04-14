import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingSettings = false

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { item in
                            MessageBubbleView(
                                item: item,
                                onDelete: {
                                    Task { await viewModel.deleteMessage(item.id) }
                                },
                                onRegenerate: {
                                    Task { await viewModel.regenerateLastResponse() }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onChange(of: viewModel.messages) { _, newMessages in
                    if let last = newMessages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            InputBarView(
                text: binding(\.inputText),
                isGenerating: viewModel.isGenerating,
                onSend: {
                    Task { await viewModel.sendMessage() }
                },
                onStop: {
                    viewModel.stopGenerating()
                }
            )
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let tokenUsage = viewModel.tokenUsage {
                    Text("\(tokenUsage.totalUsed)/\(tokenUsage.totalBudget)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            await viewModel.loadSettingsOptions()
        }
        .sheet(isPresented: $isShowingSettings) {
            ChatSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ChatViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}
