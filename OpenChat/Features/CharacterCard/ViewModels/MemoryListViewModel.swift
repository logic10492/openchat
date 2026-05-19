import Foundation
import Observation

enum MemoryReflectReviewState: Equatable, Sendable {
    case idle
    case running
    case draft
    case applying
    case failed
}

@MainActor
@Observable
final class MemoryListViewModel {
    private let databaseManager: DatabaseManager
    private let memoryManager: MemoryManager
    private let reflectExecutor: MemoryReflectExecutor
    private let apiKeyStore: any APIKeyStore
    let characterCardId: String

    private(set) var memories: [MemoryEntryRecord] = []
    private(set) var selectedMemoryIds: Set<String> = []
    private(set) var reflectState: MemoryReflectReviewState = .idle
    private(set) var reflectDraft: MemoryReflectObservation?
    private(set) var reflectDiagnostics: MemoryReflectDiagnostics?
    private(set) var reflectReviewError: MemoryReflectReviewError?
    var searchText: String = ""
    var errorMessage: String?
    var reflectErrorMessage: String?

    var filteredMemories: [MemoryEntryRecord] {
        guard !searchText.isEmpty else { return memories }
        let query = searchText.lowercased()
        return memories.filter { $0.content.lowercased().contains(query) }
    }

    var canRunReflect: Bool {
        selectedMemoryIds.count >= 2 &&
            selectedMemoryIds.count <= 5 &&
            reflectState != .running &&
            reflectState != .applying
    }

    var canApplyReflectDraft: Bool {
        reflectDraft != nil && reflectState != .running && reflectState != .applying
    }

    var isReflectBusy: Bool {
        reflectState == .running || reflectState == .applying
    }

    init(
        databaseManager: DatabaseManager,
        memoryManager: MemoryManager,
        reflectExecutor: MemoryReflectExecutor,
        apiKeyStore: any APIKeyStore,
        characterCardId: String
    ) {
        self.databaseManager = databaseManager
        self.memoryManager = memoryManager
        self.reflectExecutor = reflectExecutor
        self.apiKeyStore = apiKeyStore
        self.characterCardId = characterCardId
    }

    func loadMemories() async {
        do {
            memories = try await databaseManager.fetchMemories(characterCardId: characterCardId)
            selectedMemoryIds.formIntersection(Set(memories.map(\.id)))
        } catch {
            memories = []
            errorMessage = error.localizedDescription
        }
    }

    func isMemorySelected(_ id: String) -> Bool {
        selectedMemoryIds.contains(id)
    }

    func toggleMemorySelection(_ id: String) {
        guard !isReflectBusy else { return }

        if selectedMemoryIds.contains(id) {
            selectedMemoryIds.remove(id)
        } else {
            guard selectedMemoryIds.count < 5 else {
                setReviewError(.invalidSelectionCount(selectedMemoryIds.count + 1))
                return
            }
            selectedMemoryIds.insert(id)
        }

        reflectDraft = nil
        reflectDiagnostics = nil
        reflectReviewError = nil
        reflectErrorMessage = nil
        reflectState = .idle
    }

    func clearReflectDraft() {
        guard !isReflectBusy else { return }
        selectedMemoryIds.removeAll()
        reflectDraft = nil
        reflectDiagnostics = nil
        reflectReviewError = nil
        reflectErrorMessage = nil
        reflectState = .idle
    }

    func runReflect(task: MemoryReflectTask = .summarize) async {
        let sourceIds = selectedSourceIds()
        guard (2...5).contains(sourceIds.count) else {
            setReviewError(.invalidSelectionCount(sourceIds.count))
            return
        }

        reflectState = .running
        reflectDraft = nil
        reflectDiagnostics = nil
        reflectReviewError = nil
        reflectErrorMessage = nil

        do {
            let endpoint = try await resolveDefaultReflectEndpoint()
            let request = try MemoryReflectRequest(
                characterCardId: characterCardId,
                task: task,
                sourceMemoryIds: sourceIds
            )
            let result = try await reflectExecutor.reflect(request: request, endpoint: endpoint)
            reflectDraft = result.observation
            reflectDiagnostics = result.diagnostics
            reflectState = .draft
        } catch let error as MemoryReflectReviewError {
            setReviewError(error)
        } catch {
            reflectReviewError = nil
            reflectErrorMessage = error.localizedDescription
            reflectState = .failed
        }
    }

    func applyReflectObservation() async {
        guard let draft = reflectDraft else {
            setReviewError(.noDraft)
            return
        }

        reflectState = .applying
        reflectReviewError = nil
        reflectErrorMessage = nil

        do {
            _ = try await memoryManager.applyReflectObservation(draft, characterCardId: characterCardId)
            memories = try await databaseManager.fetchMemories(characterCardId: characterCardId)
            selectedMemoryIds.removeAll()
            reflectDraft = nil
            reflectDiagnostics = nil
            reflectState = .idle
        } catch let error as MemoryReflectReviewError {
            setReviewError(error)
        } catch let error as MemoryReflectApplyError {
            reflectReviewError = nil
            reflectErrorMessage = localizedMessage(for: error)
            reflectState = .failed
        } catch {
            reflectReviewError = nil
            reflectErrorMessage = error.localizedDescription
            reflectState = .failed
        }
    }

    func deleteMemory(_ id: String) async {
        do {
            try await memoryManager.deleteMemory(id: id)
            memories.removeAll { $0.id == id }
            selectedMemoryIds.remove(id)
            if reflectDraft?.basedOnMemoryIds.contains(id) == true {
                reflectDraft = nil
                reflectDiagnostics = nil
                reflectState = .idle
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllMemories() async {
        do {
            try await memoryManager.deleteAllMemories(for: characterCardId)
            memories.removeAll()
            selectedMemoryIds.removeAll()
            reflectDraft = nil
            reflectDiagnostics = nil
            reflectReviewError = nil
            reflectErrorMessage = nil
            reflectState = .idle
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectedSourceIds() -> [String] {
        memories
            .map(\.id)
            .filter { selectedMemoryIds.contains($0) }
    }

    private func resolveDefaultReflectEndpoint() async throws -> APIEndpointConfig {
        guard let endpoint = try await databaseManager.fetchDefaultEndpoint() else {
            throw MemoryReflectReviewError.noDefaultEndpoint
        }
        guard let model = try await databaseManager.fetchDefaultModel(endpointId: endpoint.id) else {
            throw MemoryReflectReviewError.noDefaultModel(endpointId: endpoint.id)
        }
        let storedKey = try apiKeyStore.readKey(endpointId: endpoint.id)
        guard let apiKey = (storedKey ?? endpoint.apiKey)?.nilIfBlank else {
            throw MemoryReflectReviewError.missingAPIKey(endpointId: endpoint.id)
        }
        return try APIEndpointConfig(from: endpoint, model: model, apiKey: apiKey)
    }

    private func setReviewError(_ error: MemoryReflectReviewError) {
        reflectReviewError = error
        reflectErrorMessage = localizedMessage(for: error)
        reflectState = .failed
    }

    private func localizedMessage(for error: MemoryReflectReviewError) -> String {
        switch error {
        case .invalidSelectionCount:
            String(localized: "Select 2 to 5 memories before organizing.")
        case .noDefaultEndpoint:
            String(localized: "No default API endpoint configured.")
        case .noDefaultModel:
            String(localized: "Default endpoint has no default model.")
        case .missingAPIKey:
            String(localized: "Default endpoint is missing an API key.")
        case .noDraft:
            String(localized: "No reflect draft is available to apply.")
        }
    }

    private func localizedMessage(for error: MemoryReflectApplyError) -> String {
        switch error {
        case .unsupportedAction:
            String(localized: "Only insert observations can be applied automatically.")
        }
    }
}
