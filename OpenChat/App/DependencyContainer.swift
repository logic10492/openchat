import Foundation
import Observation

@Observable
final class DependencyContainer {
    let databaseManager: DatabaseManager
    let apiClient: APIClient
    let contextManager: ContextManager
    let memoryManager: MemoryManager
    let titleGenerator: TitleGenerator

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient? = nil
    ) {
        self.databaseManager = databaseManager
        let resolvedClient = apiClient ?? APIClient()
        self.apiClient = resolvedClient
        self.contextManager = ContextManager(
            databaseManager: databaseManager,
            apiClient: resolvedClient
        )
        self.memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: EmbeddingService(),
            vectorStore: VectorStore(databaseManager: databaseManager),
            apiClient: resolvedClient
        )
        self.titleGenerator = TitleGenerator(apiClient: resolvedClient)
    }

    static func live() throws -> DependencyContainer {
        try DependencyContainer(databaseManager: DatabaseManager.live())
    }

    static func preview() -> DependencyContainer {
        if let databaseManager = try? DatabaseManager.inMemory() {
            return DependencyContainer(databaseManager: databaseManager)
        }
        if let databaseManager = try? DatabaseManager.live() {
            return DependencyContainer(databaseManager: databaseManager)
        }
        fatalError("Unable to create a preview dependency container.")
    }
}
