import Foundation
import Testing

@testable import OpenChat

@Suite("ModelObject")
struct ModelObjectTests {
    // MARK: - applyContextLength

    @MainActor
    @Test func test_applyContextLength_sets_value_when_model_has_contextLength() throws {
        let db = try TestHelpers.makeDatabaseManager()
        let client = APIClient(session: .shared)
        let vm = APIEndpointEditorViewModel(databaseManager: db, apiClient: client)

        vm.fetchedModels = [
            ModelObject(id: "llama-3", object: "model", ownedBy: "meta", contextLength: 65_536),
            ModelObject(id: "gpt-4o", object: "model", ownedBy: "openai", contextLength: nil),
        ]

        vm.applyContextLength(for: "llama-3")
        #expect(vm.maxContextTokens == 65_536)
        #expect(vm.contextLengthAutoDetected == true)
    }

    @MainActor
    @Test func test_applyContextLength_does_not_change_when_model_has_no_contextLength() throws {
        let db = try TestHelpers.makeDatabaseManager()
        let client = APIClient(session: .shared)
        let vm = APIEndpointEditorViewModel(databaseManager: db, apiClient: client)
        let original = vm.maxContextTokens

        vm.fetchedModels = [
            ModelObject(id: "gpt-4o", object: "model", ownedBy: "openai", contextLength: nil),
        ]

        vm.applyContextLength(for: "gpt-4o")
        #expect(vm.maxContextTokens == original)
        #expect(vm.contextLengthAutoDetected == false)
    }

    @MainActor
    @Test func test_applyContextLength_does_not_change_for_unknown_model() throws {
        let db = try TestHelpers.makeDatabaseManager()
        let client = APIClient(session: .shared)
        let vm = APIEndpointEditorViewModel(databaseManager: db, apiClient: client)
        let original = vm.maxContextTokens

        vm.fetchedModels = [
            ModelObject(id: "llama-3", object: "model", ownedBy: "meta", contextLength: 65_536),
        ]

        vm.applyContextLength(for: "unknown-model")
        #expect(vm.maxContextTokens == original)
        #expect(vm.contextLengthAutoDetected == false)
    }
}
