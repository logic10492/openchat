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
    let backgroundManager: BackgroundManager
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
        let memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: embeddingService,
            vectorStore: VectorStore(databaseManager: databaseManager),
            apiClient: resolvedClient,
            apiKeyStore: apiKeyStore
        )
        self.memoryManager = memoryManager
        self.worldBookVectorStore = worldBookVectorStore
        self.worldBookEmbeddingIndexer = WorldBookEmbeddingIndexer(
            databaseManager: databaseManager,
            embeddingProvider: embeddingService,
            vectorStore: worldBookVectorStore
        )
        let worldBookSource = WorldBookSource(
            embeddingProvider: embeddingService,
            vectorStore: worldBookVectorStore
        )
        self.worldBookSource = worldBookSource
        self.backgroundManager = BackgroundManager(
            sources: [
                MemoryBackgroundSource(tool: MemoryRecallTool(memoryManager: memoryManager)),
                WorldBookBackgroundSource(tool: WorldBookRecallTool(source: worldBookSource)),
            ]
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
