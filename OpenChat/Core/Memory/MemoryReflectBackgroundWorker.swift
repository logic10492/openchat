import Foundation

struct MemoryReflectBackgroundPolicy: Sendable, Equatable {
    let minimumMemories: Int
    let maximumSourceMemories: Int
    let minimumInterval: TimeInterval

    static let idleDefault = MemoryReflectBackgroundPolicy(
        minimumMemories: 3,
        maximumSourceMemories: 5,
        minimumInterval: 6 * 60 * 60
    )
}

enum MemoryReflectBackgroundSkipReason: String, Sendable, Equatable {
    case noCharacter
    case tooSoon
    case insufficientMemories
    case requestAlreadyRunning
}

struct MemoryReflectBackgroundResult: Sendable {
    let observation: MemoryReflectObservation?
    let diagnostics: MemoryReflectDiagnostics?
    let skippedReason: MemoryReflectBackgroundSkipReason?

    static func skipped(_ reason: MemoryReflectBackgroundSkipReason) -> MemoryReflectBackgroundResult {
        MemoryReflectBackgroundResult(observation: nil, diagnostics: nil, skippedReason: reason)
    }
}

actor MemoryReflectBackgroundWorker {
    private let databaseManager: DatabaseManager
    private let reflectExecutor: MemoryReflectExecutor
    private let policy: MemoryReflectBackgroundPolicy
    private var lastRunByCharacter: [String: Date] = [:]
    private var runningCharacters: Set<String> = []

    init(
        databaseManager: DatabaseManager,
        reflectExecutor: MemoryReflectExecutor,
        policy: MemoryReflectBackgroundPolicy = .idleDefault
    ) {
        self.databaseManager = databaseManager
        self.reflectExecutor = reflectExecutor
        self.policy = policy
    }

    func prepareIdleDraft(
        characterCardId: String?,
        endpoint: APIEndpointConfig,
        now: Date = .now
    ) async throws -> MemoryReflectBackgroundResult {
        guard let characterCardId = characterCardId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !characterCardId.isEmpty else {
            return .skipped(.noCharacter)
        }

        if runningCharacters.contains(characterCardId) {
            return .skipped(.requestAlreadyRunning)
        }

        if let lastRun = lastRunByCharacter[characterCardId],
           now.timeIntervalSince(lastRun) < policy.minimumInterval {
            return .skipped(.tooSoon)
        }

        let sourceMemories = try await databaseManager.fetchRecentHighValueMemories(
            characterCardId: characterCardId,
            limit: policy.maximumSourceMemories
        )
        guard sourceMemories.count >= policy.minimumMemories else {
            return .skipped(.insufficientMemories)
        }

        runningCharacters.insert(characterCardId)
        defer { runningCharacters.remove(characterCardId) }

        let request = try MemoryReflectRequest(
            characterCardId: characterCardId,
            task: .summarize,
            sourceMemoryIds: sourceMemories.map(\.id)
        )
        let result = try await reflectExecutor.reflect(
            request: request,
            endpoint: endpoint,
            requestId: "idle-reflect-\(characterCardId)-\(Int(now.timeIntervalSince1970))"
        )
        lastRunByCharacter[characterCardId] = now
        return MemoryReflectBackgroundResult(
            observation: result.observation,
            diagnostics: result.diagnostics,
            skippedReason: nil
        )
    }
}
