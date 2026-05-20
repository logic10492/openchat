import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient
    private let apiKeyStore: any APIKeyStore
    private let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer
    private let appState: AppState
    private let defaults = UserDefaults.standard

    private(set) var endpoints: [APIEndpointRecord] = []
    var defaultTemperature = AppConstants.defaultTemperature
    var defaultTopP = AppConstants.defaultTopP
    var defaultMaxTokens: Int?
    var defaultFrequencyPenalty = 0.0
    var defaultPresencePenalty = 0.0
    var defaultContextStrategy = ContextStrategy.truncation
    var compressionEndpointId: String?
    var showDetailedStats = false
    private(set) var isRebuildingWorldBookIndex = false
    var worldBookIndexStatusMessage: String?

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer,
        appState: AppState
    ) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.apiKeyStore = apiKeyStore
        self.worldBookEmbeddingIndexer = worldBookEmbeddingIndexer
        self.appState = appState
        loadDefaults()
    }

    func loadEndpoints() async {
        do {
            endpoints = try await databaseManager.fetchEndpoints()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func deleteEndpoint(_ id: String) async {
        do {
            try await databaseManager.deleteEndpoint(id: id)
            try apiKeyStore.deleteKey(endpointId: id)
            await loadEndpoints()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func setDefaultEndpoint(_ id: String) async {
        do {
            guard var endpoint = try await databaseManager.fetchEndpoint(id: id) else { return }
            endpoint.isDefault = true
            endpoint.updatedAt = .now
            try await databaseManager.saveEndpoint(endpoint)
            await loadEndpoints()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func resetModelParameters() {
        defaultTemperature = AppConstants.defaultTemperature
        defaultTopP = AppConstants.defaultTopP
        defaultMaxTokens = nil
        defaultFrequencyPenalty = 0
        defaultPresencePenalty = 0
        defaultContextStrategy = AppConstants.defaultContextStrategy
        persistDefaults()
    }

    func persistDefaults() {
        defaults.set(defaultTemperature, forKey: "default_temperature")
        defaults.set(defaultTopP, forKey: "default_top_p")
        defaults.set(defaultMaxTokens, forKey: "default_max_tokens")
        defaults.set(defaultFrequencyPenalty, forKey: "default_frequency_penalty")
        defaults.set(defaultPresencePenalty, forKey: "default_presence_penalty")
        defaults.set(defaultContextStrategy.rawValue, forKey: "default_context_strategy")
        defaults.set(compressionEndpointId, forKey: "compression_endpoint_id")
        defaults.set(showDetailedStats, forKey: "show_detailed_stats")
    }

    func exportAllData() async throws -> URL {
        throw DatabaseError.exportFailed("Export is not wired yet.")
    }

    func importData(from url: URL) async throws {
        _ = url
        throw DatabaseError.importFailed("Import is not wired yet.")
    }

    func clearAllData() async {
        do {
            try await databaseManager.eraseAllData()
        } catch {
            appState.present(error: error.localizedDescription)
        }
    }

    func rebuildWorldBookSemanticIndex() async {
        guard !isRebuildingWorldBookIndex else { return }
        isRebuildingWorldBookIndex = true
        worldBookIndexStatusMessage = nil
        defer { isRebuildingWorldBookIndex = false }

        do {
            let result = try await worldBookEmbeddingIndexer.rebuildAllMissingOrStale(limit: nil)
            worldBookIndexStatusMessage = String.localizedStringWithFormat(
                String(localized: "World book semantic index check complete: %lld indexed, %lld newly indexed, %lld failed."),
                result.skippedFreshCount,
                result.indexedCount,
                result.failed.count
            )
        } catch {
            worldBookIndexStatusMessage = error.localizedDescription
            appState.present(error: error.localizedDescription)
        }
    }

    func makeDefaultParameters() -> ModelParameters {
        ModelParameters(
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            frequencyPenalty: defaultFrequencyPenalty,
            presencePenalty: defaultPresencePenalty,
            stop: nil
        )
    }

    private func loadDefaults() {
        if defaults.object(forKey: "default_temperature") != nil {
            defaultTemperature = defaults.double(forKey: "default_temperature")
        }
        if defaults.object(forKey: "default_top_p") != nil {
            defaultTopP = defaults.double(forKey: "default_top_p")
        }
        if defaults.object(forKey: "default_max_tokens") != nil {
            defaultMaxTokens = defaults.integer(forKey: "default_max_tokens")
        }
        if defaults.object(forKey: "default_frequency_penalty") != nil {
            defaultFrequencyPenalty = defaults.double(forKey: "default_frequency_penalty")
        }
        if defaults.object(forKey: "default_presence_penalty") != nil {
            defaultPresencePenalty = defaults.double(forKey: "default_presence_penalty")
        }
        if let rawValue = defaults.string(forKey: "default_context_strategy"),
           let strategy = ContextStrategy(rawValue: rawValue) {
            defaultContextStrategy = strategy
        }
        compressionEndpointId = defaults.string(forKey: "compression_endpoint_id")
        showDetailedStats = defaults.bool(forKey: "show_detailed_stats")
    }
}
