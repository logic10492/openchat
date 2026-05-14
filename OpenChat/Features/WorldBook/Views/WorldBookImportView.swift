import SwiftUI

struct WorldBookImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    let onImport: ([WorldBookImportFormat.ParsedEntry]) async throws -> Void

    init(onImport: @escaping ([WorldBookImportFormat.ParsedEntry]) async throws -> Void) {
        self.onImport = onImport
    }

    private var parsedEntries: [WorldBookImportFormat.ParsedEntry] {
        WorldBookImportFormat.parse(text: text)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                List(parsedEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        Text(entry.keywords.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(entry.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle(String(localized: "Import World Book"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Import")) {
                        Task {
                            isImporting = true
                            errorMessage = nil
                            defer { isImporting = false }

                            do {
                                try await onImport(parsedEntries)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(parsedEntries.isEmpty || isImporting)
                }
            }
        }
    }
}
