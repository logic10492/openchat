import Foundation
import Testing

@Suite("Critical save flow source rules")
struct CriticalSaveFlowTests {
    @Test func test_editor_views_do_not_silently_dismiss_after_failed_save() throws {
        let files = [
            "OpenChat/Features/Settings/Views/APIEndpointEditorView.swift",
            "OpenChat/Features/CharacterCard/Views/CharacterCardEditorView.swift",
            "OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift",
        ]

        for file in files {
            let contents = try String(contentsOf: repositoryRoot().appending(path: file), encoding: .utf8)
            #expect(!contents.contains("try? await viewModel.save()"), "Silent save in \(file)")
            #expect(!contents.contains("try? await viewModel.saveEntry"), "Silent entry save in \(file)")
        }
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
