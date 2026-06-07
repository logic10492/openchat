import SwiftUI

struct CharacterSkillBundleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CharacterSkillBundleEditorViewModel

    init(viewModel: CharacterSkillBundleEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.isLoading {
                    ProgressView(String(localized: "Loading"))
                } else {
                    CharacterSkillSummarySection(
                        skillName: viewModel.skillName,
                        skillDescription: viewModel.skillDescription,
                        referenceCount: viewModel.referenceDrafts.count
                    )

                    Section(String(localized: "World Book")) {
                        Picker(String(localized: "World Book"), selection: worldBookIdBinding) {
                            Text(String(localized: "None")).tag(String?.none)
                            ForEach(viewModel.availableWorldBooks) { book in
                                Text(book.name).tag(Optional(book.id))
                            }
                        }
                    }

                    Section(String(localized: "SKILL.md")) {
                        TextField(
                            String(localized: "Role skill markdown"),
                            text: skillMarkdownBinding,
                            axis: .vertical
                        )
                        .font(.body.monospaced())
                        .lineLimit(12...)
                    }

                    CharacterSkillReferencesSection(
                        referenceDrafts: viewModel.referenceDrafts,
                        textBinding: referenceMarkdownBinding
                    )

                    CharacterSkillPreviewSection(previewText: viewModel.roleSkillPreview)

                    if !viewModel.validationErrors.isEmpty {
                        Section(String(localized: "Validation")) {
                            ForEach(viewModel.validationErrors, id: \.self) { message in
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Edit Role Skill"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel"), action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save"), action: save)
                        .disabled(!viewModel.isValid || viewModel.isSaving || viewModel.isLoading)
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }

    private var skillMarkdownBinding: Binding<String> {
        @Bindable var viewModel = viewModel
        return $viewModel.skillMarkdown
    }

    private var worldBookIdBinding: Binding<String?> {
        @Bindable var viewModel = viewModel
        return $viewModel.worldBookId
    }

    private func referenceMarkdownBinding(_ draft: CharacterSkillReferenceDraft) -> Binding<String> {
        Binding(
            get: {
                viewModel.referenceDrafts.first { $0.id == draft.id }?.markdown ?? ""
            },
            set: { value in
                guard let index = viewModel.referenceDrafts.firstIndex(where: { $0.id == draft.id }) else {
                    return
                }
                viewModel.referenceDrafts[index].markdown = value
            }
        )
    }

    private func save() {
        Task {
            do {
                _ = try await viewModel.save()
                dismiss()
            } catch {
                // ViewModel owns the visible error message.
            }
        }
    }
}
