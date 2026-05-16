import SwiftUI

struct WorldBookEditorView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WorldBookEditorViewModel
    @State private var editingEntry: WorldBookEntryRecord?
    @State private var importText = ""
    @State private var isShowingImport = false
    @State private var editingCharacterCard: CharacterCardRecord?
    @State private var selectedCharacterCard: CharacterCardRecord?

    init(viewModel: WorldBookEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Basic")) {
                    TextField(String(localized: "Name"), text: bind(\.name))
                    TextField(String(localized: "Description"), text: bind(\.description), axis: .vertical)
                    Toggle(String(localized: "Enabled"), isOn: bind(\.isEnabled))
                }

                if viewModel.editingWorldBook != nil {
                    Section(String(localized: "Characters")) {
                        ForEach(viewModel.characters) { card in
                            Button {
                                selectedCharacterCard = card
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(card.name)
                                            .font(.subheadline.weight(.medium))
                                        if !card.decodedTags.isEmpty {
                                            Text(card.decodedTags.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button(String(localized: "New Character")) {
                            editingCharacterCard = CharacterCardRecord(
                                id: "",
                                name: "",
                                avatar: nil,
                                personality: nil,
                                appearance: nil,
                                physique: nil,
                                speechStyle: nil,
                                backstory: nil,
                                systemPrompt: nil,
                                scenario: nil,
                                exampleDialogs: nil,
                                creatorNotes: nil,
                                tags: nil,
                                worldBookId: viewModel.editingWorldBook?.id,
                                createdAt: .now,
                                updatedAt: .now
                            )
                        }
                    }
                }

                Section(String(localized: "Entries")) {
                    ForEach(viewModel.entries) { entry in
                        Button(entry.title) {
                            editingEntry = entry
                        }
                    }

                    Button(String(localized: "Add Entry")) {
                        let worldBookId = viewModel.currentWorldBookId ?? UUID().uuidString
                        editingEntry = WorldBookEntryRecord(
                            id: UUID().uuidString,
                            worldBookId: worldBookId,
                            title: "",
                            content: "",
                            keywords: "[]",
                            priority: 50,
                            isEnabled: true,
                            position: "before_history",
                            createdAt: .now,
                            updatedAt: .now
                        )
                    }

                    Button(String(localized: "Import Markdown")) {
                        isShowingImport = true
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let indexingWarningMessage = viewModel.indexingWarningMessage {
                    Section {
                        Text(indexingWarningMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(viewModel.editingWorldBook == nil ? String(localized: "New World Book") : String(localized: "Edit World Book"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
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
                    .disabled(viewModel.name.nilIfBlank == nil || viewModel.isSaving)
                }
            }
            .task {
                await viewModel.loadEntries()
                await viewModel.loadCharacters()
            }
            .sheet(item: $editingEntry, onDismiss: reloadEntries) { entry in
                WorldBookEntryEditorView(
                    entry: entry,
                    onSave: { updatedEntry in
                        try await viewModel.saveEntry(updatedEntry)
                    }
                )
            }
            .sheet(isPresented: $isShowingImport) {
                WorldBookImportView { parsedEntries in
                    _ = try await viewModel.importEntries(parsedEntries)
                }
            }
            .sheet(item: $editingCharacterCard, onDismiss: reloadCharacters) { card in
                CharacterCardEditorView(
                    viewModel: CharacterCardEditorViewModel(
                        databaseManager: container.databaseManager,
                        editingCard: card.id.isEmpty ? nil : card,
                        defaultWorldBookId: viewModel.editingWorldBook?.id
                    )
                )
            }
            .sheet(item: $selectedCharacterCard, onDismiss: reloadCharacters) { card in
                CharacterCardDetailView(
                    card: card,
                    onEdit: {
                        selectedCharacterCard = nil
                        editingCharacterCard = card
                    }
                )
            }
        }
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<WorldBookEditorViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private func reloadEntries() {
        Task {
            await viewModel.loadEntries()
        }
    }

    private func reloadCharacters() {
        Task {
            await viewModel.loadCharacters()
        }
    }
}
