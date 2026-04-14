import SwiftUI

struct WorldBookImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let onImport: ([WorldBookImportFormat.ParsedEntry]) -> Void

    init(onImport: @escaping ([WorldBookImportFormat.ParsedEntry]) -> Void) {
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
            }
            .padding()
            .navigationTitle(String(localized: "Import World Book"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Import")) {
                        onImport(parsedEntries)
                        dismiss()
                    }
                    .disabled(parsedEntries.isEmpty)
                }
            }
        }
    }
}
