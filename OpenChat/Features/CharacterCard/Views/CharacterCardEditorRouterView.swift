import SwiftUI

struct CharacterCardEditorRouterView: View {
    let databaseManager: DatabaseManager
    let skillBundleStore: CharacterSkillBundleStore
    let card: CharacterCardRecord
    let defaultWorldBookId: String?
    @State private var bundle: CharacterSkillBundleRecord?
    @State private var isLoading = false
    @State private var didLoadBundle = false

    var body: some View {
        Group {
            if card.id.isEmpty {
                standardEditor
            } else if !didLoadBundle || isLoading {
                loadingView
            } else if let bundle {
                CharacterSkillBundleEditorView(
                    viewModel: CharacterSkillBundleEditorViewModel(
                        databaseManager: databaseManager,
                        skillBundleStore: skillBundleStore,
                        editingCard: card,
                        editingBundle: bundle
                    )
                )
            } else {
                standardEditor
            }
        }
        .task(id: card.id) {
            await loadBundle()
        }
    }

    private var standardEditor: some View {
        CharacterCardEditorView(
            viewModel: CharacterCardEditorViewModel(
                databaseManager: databaseManager,
                editingCard: card.id.isEmpty ? nil : card,
                defaultWorldBookId: defaultWorldBookId
            )
        )
    }

    private var loadingView: some View {
        NavigationStack {
            ProgressView(String(localized: "Loading"))
                .navigationTitle(String(localized: "Edit Character"))
        }
    }

    private func loadBundle() async {
        guard !card.id.isEmpty else { return }
        didLoadBundle = false
        isLoading = true
        defer { isLoading = false }
        do {
            bundle = try await databaseManager.fetchCharacterSkillBundle(characterCardId: card.id)
        } catch {
            bundle = nil
        }
        didLoadBundle = true
    }
}
