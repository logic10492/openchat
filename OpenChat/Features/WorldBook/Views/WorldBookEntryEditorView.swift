import SwiftUI

struct WorldBookEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var keywords: String
    @State private var content: String
    @State private var priority: Double
    @State private var position: String
    @State private var isEnabled: Bool

    let entry: WorldBookEntryRecord
    let onSave: (WorldBookEntryRecord) -> Void

    init(
        entry: WorldBookEntryRecord,
        onSave: @escaping (WorldBookEntryRecord) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _keywords = State(initialValue: entry.decodedKeywords.joined(separator: ", "))
        _content = State(initialValue: entry.content)
        _priority = State(initialValue: Double(entry.priority))
        _position = State(initialValue: entry.position)
        _isEnabled = State(initialValue: entry.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Title"), text: $title)
                TextField(String(localized: "Keywords"), text: $keywords)
                TextField(String(localized: "Content"), text: $content, axis: .vertical)
                Slider(value: $priority, in: 0...100, step: 1) {
                    Text(String(localized: "Priority"))
                }
                Picker(String(localized: "Position"), selection: $position) {
                    Text("after_system").tag("after_system")
                    Text("before_history").tag("before_history")
                }
                Toggle(String(localized: "Enabled"), isOn: $isEnabled)
            }
            .navigationTitle(String(localized: "Entry"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        onSave(
                            WorldBookEntryRecord(
                                id: entry.id,
                                worldBookId: entry.worldBookId,
                                title: title,
                                content: content,
                                keywords: RecordCoders.encode(
                                    keywords
                                        .split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                ) ?? "[]",
                                priority: Int(priority),
                                isEnabled: isEnabled,
                                position: position,
                                createdAt: entry.createdAt,
                                updatedAt: .now
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
