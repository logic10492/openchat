import SwiftUI

struct CharacterCardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CharacterCardEditorViewModel

    init(viewModel: CharacterCardEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Basic")) {
                    TextField(String(localized: "Name"), text: bind(\.name))
                    TextField(String(localized: "Tags (comma separated)"), text: tagsBinding)
                    TextField(String(localized: "Creator Notes"), text: bind(\.creatorNotes), axis: .vertical)
                    Picker(String(localized: "World Book"), selection: worldBookIdBinding) {
                        Text(String(localized: "None")).tag(String?.none)
                        ForEach(viewModel.availableWorldBooks) { book in
                            Text(book.name).tag(Optional(book.id))
                        }
                    }
                }

                Section(String(localized: "Description")) {
                    TextField(String(localized: "Personality"), text: bind(\.personality), axis: .vertical)
                    TextField(String(localized: "Appearance"), text: bind(\.appearance), axis: .vertical)
                    TextField(String(localized: "Physique"), text: bind(\.physique), axis: .vertical)
                    TextField(String(localized: "Speech Style"), text: bind(\.speechStyle), axis: .vertical)
                    TextField(String(localized: "Backstory"), text: bind(\.backstory), axis: .vertical)
                }

                Section(String(localized: "Prompt")) {
                    TextField(String(localized: "System Prompt"), text: bind(\.systemPrompt), axis: .vertical)
                    TextField(String(localized: "Scenario"), text: bind(\.scenario), axis: .vertical)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.editingCard == nil ? String(localized: "New Character") : String(localized: "Edit Character"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task {
                            do {
                                _ = try await viewModel.save()
                                dismiss()
                            } catch {
                                // ViewModel owns the visible error message.
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadWorldBooks()
            }
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<CharacterCardEditorViewModel, String>) -> Binding<String> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { viewModel.tags.joined(separator: ", ") },
            set: { value in
                viewModel.tags = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var worldBookIdBinding: Binding<String?> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel.worldBookId },
            set: { viewModel.worldBookId = $0 }
        )
    }
}
