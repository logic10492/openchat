import SwiftUI

struct CharacterCardImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    let onImport: (CharacterCardImportFormat.ParsedCard) async throws -> Void

    init(onImport: @escaping (CharacterCardImportFormat.ParsedCard) async throws -> Void) {
        self.onImport = onImport
    }

    private var parsedCard: CharacterCardImportFormat.ParsedCard? {
        try? CharacterCardImportFormat.parse(text: text)
    }

    var body: some View {
        NavigationStack {
            content
            .navigationTitle(String(localized: "Import Character"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Import")) {
                        Task { await importCurrentCard() }
                    }
                    .disabled(parsedCard == nil || isImporting)
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            previewContent

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var previewContent: some View {
        if let parsedCard {
            List {
                VStack(alignment: .leading, spacing: 8) {
                    Text(parsedCard.name)
                        .font(.headline)
                    if !parsedCard.tags.isEmpty {
                        Text(parsedCard.tags.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(parsedCard.formatSummary)
                        .font(.caption)
                        .foregroundStyle(parsedCard.warnings.isEmpty ? Color.secondary : Color.orange)
                }
            }
        } else {
            EmptyStateView(
                title: String(localized: "Paste Character JSON"),
                message: String(localized: "OpenChat and SillyTavern V2 character cards are supported."),
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private func importCurrentCard() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            let card = try CharacterCardImportFormat.parse(text: text)
            try await onImport(card)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CharacterCardImportView { _ in }
}
