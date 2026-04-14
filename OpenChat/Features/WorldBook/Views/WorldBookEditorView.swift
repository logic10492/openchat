import SwiftUI

struct WorldBookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WorldBookEditorViewModel
    @State private var editingEntry: WorldBookEntryRecord?
    @State private var importText = ""
    @State private var isShowingImport = false

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

                Section(String(localized: "Entries")) {
                    ForEach(viewModel.entries) { entry in
                        Button(entry.title) {
                            editingEntry = entry
                        }
                    }

                    Button(String(localized: "Add Entry")) {
                        let worldBookId = viewModel.editingWorldBook?.id ?? UUID().uuidString
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
            }
            .navigationTitle(viewModel.editingWorldBook == nil ? String(localized: "New World Book") : String(localized: "Edit World Book"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task {
                            _ = try? await viewModel.save()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.name.nilIfBlank == nil)
                }
            }
            .task {
                await viewModel.loadEntries()
            }
            .sheet(item: $editingEntry, onDismiss: reloadEntries) { entry in
                WorldBookEntryEditorView(
                    entry: entry,
                    onSave: { updatedEntry in
                        Task {
                            try? await viewModel.saveEntry(updatedEntry)
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingImport) {
                WorldBookImportView { parsedEntries in
                    Task {
                        let worldBook = try? await viewModel.save()
                        guard let worldBook else { return }
                        for parsed in parsedEntries {
                            let entry = WorldBookEntryRecord(
                                id: UUID().uuidString,
                                worldBookId: worldBook.id,
                                title: parsed.title,
                                content: parsed.content,
                                keywords: RecordCoders.encode(parsed.keywords) ?? "[]",
                                priority: parsed.priority,
                                isEnabled: true,
                                position: parsed.position,
                                createdAt: .now,
                                updatedAt: .now
                            )
                            try? await viewModel.saveEntry(entry)
                        }
                        await viewModel.loadEntries()
                    }
                }
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
}
