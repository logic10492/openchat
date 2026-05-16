import Foundation
import Observation

@Observable
final class DependencyContainer {
    let databaseManager: DatabaseManager
    let apiClient: APIClient
    let apiKeyStore: any APIKeyStore
    let contextManager: ContextManager
    let memoryManager: MemoryManager
    let worldBookVectorStore: WorldBookVectorStore
    let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer
    let worldBookSource: WorldBookSource
    let titleGenerator: TitleGenerator

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient? = nil,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()
    ) {
        self.databaseManager = databaseManager
        let resolvedClient = apiClient ?? APIClient()
        self.apiClient = resolvedClient
        self.apiKeyStore = apiKeyStore
        let embeddingService = EmbeddingService()
        let worldBookVectorStore = WorldBookVectorStore(databaseManager: databaseManager)
        self.contextManager = ContextManager(
            databaseManager: databaseManager,
            apiClient: resolvedClient
        )
        self.memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: embeddingService,
            vectorStore: VectorStore(databaseManager: databaseManager),
            apiClient: resolvedClient,
            apiKeyStore: apiKeyStore
        )
        self.worldBookVectorStore = worldBookVectorStore
        self.worldBookEmbeddingIndexer = WorldBookEmbeddingIndexer(
            databaseManager: databaseManager,
            embeddingProvider: embeddingService,
            vectorStore: worldBookVectorStore
        )
        self.worldBookSource = WorldBookSource(
            embeddingProvider: embeddingService,
            vectorStore: worldBookVectorStore
        )
        self.titleGenerator = TitleGenerator(apiClient: resolvedClient)
    }

    static func live() throws -> DependencyContainer {
        try DependencyContainer(
            databaseManager: DatabaseManager.live(),
            apiKeyStore: KeychainAPIKeyStore()
        )
    }

    static func preview() -> DependencyContainer {
        if let databaseManager = try? DatabaseManager.inMemory() {
            return DependencyContainer(
                databaseManager: databaseManager,
                apiKeyStore: InMemoryAPIKeyStore()
            )
        }
        if let databaseManager = try? DatabaseManager.live() {
            return DependencyContainer(
                databaseManager: databaseManager,
                apiKeyStore: InMemoryAPIKeyStore()
            )
        }
        fatalError("Unable to create a preview dependency container.")
    }
}
