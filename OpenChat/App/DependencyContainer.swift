import Foundation
import Observation

@Observable
final class DependencyContainer {
    let databaseManager: DatabaseManager
    let apiClient: APIClient
    let apiKeyStore: any APIKeyStore
    let contextManager: ContextManager
    let memoryManager: MemoryManager
    let memoryReflectExecutor: MemoryReflectExecutor
    let memoryReflectBackgroundWorker: MemoryReflectBackgroundWorker
    let worldBookVectorStore: WorldBookVectorStore
    let worldBookEmbeddingIndexer: WorldBookEmbeddingIndexer
    let worldBookSource: WorldBookSource
    let backgroundManager: BackgroundManager
    let titleGenerator: TitleGenerator
    let skillBundleStore: CharacterSkillBundleStore
    let skillBundleMaterializer: CharacterSkillBundleMaterializer

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient? = nil,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        skillBundleStore: CharacterSkillBundleStore? = nil
    ) {
        self.databaseManager = databaseManager
        let resolvedClient = apiClient ?? APIClient()
        self.apiClient = resolvedClient
        self.apiKeyStore = apiKeyStore
        let resolvedSkillBundleStore = skillBundleStore
            ?? (try? CharacterSkillBundleStore.live())
            ?? CharacterSkillBundleStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appending(path: "OpenChatSkillBundles", directoryHint: .isDirectory)
        )
        self.skillBundleStore = resolvedSkillBundleStore
        self.skillBundleMaterializer = CharacterSkillBundleMaterializer(
            databaseManager: databaseManager,
            store: resolvedSkillBundleStore
        )
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
        self.memoryReflectExecutor = MemoryReflectExecutor(
            databaseManager: databaseManager,
            apiClient: resolvedClient
        )
        self.memoryReflectBackgroundWorker = MemoryReflectBackgroundWorker(
            databaseManager: databaseManager,
            reflectExecutor: memoryReflectExecutor
        )
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
                CharacterStateBackgroundSource(),
                ConversationStateBackgroundSource(),
                SkillReferenceBackgroundSource(
                    tool: SkillReferenceSearchTool(
                        databaseManager: databaseManager,
                        store: resolvedSkillBundleStore
                    )
                ),
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
