import SwiftUI
import UniformTypeIdentifiers

struct CharacterCardImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false
    @State private var isShowingFileImporter = false
    @State private var errorMessage: String?
    let onImportText: (String) async throws -> Void
    let onImportFile: (Data, String?) async throws -> Void

    init(
        onImportText: @escaping (String) async throws -> Void,
        onImportFile: @escaping (Data, String?) async throws -> Void
    ) {
        self.onImportText = onImportText
        self.onImportFile = onImportFile
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
            fileImportButton

            Divider()

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
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: Self.supportedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result)
        }
    }

    private var fileImportButton: some View {
        Button {
            isShowingFileImporter = true
        } label: {
            Label(String(localized: "Choose ZIP or JSON File"), systemImage: "archivebox")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isImporting)
        .accessibilityHint(
            String(localized: "Skill ZIP bundles and OpenChat JSON files are supported.")
        )
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
                message: String(localized: "Skill ZIP bundles and OpenChat JSON files are supported."),
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private func importCurrentCard() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            try await onImportText(text)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importFile(at: url) }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(at url: URL) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await onImportFile(data, url.lastPathComponent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var supportedFileTypes: [UTType] {
        [
            .json,
            UTType(filenameExtension: "zip") ?? .data,
        ]
    }
}

#Preview {
    CharacterCardImportView(
        onImportText: { _ in },
        onImportFile: { _, _ in }
    )
}
