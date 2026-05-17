import Foundation

struct MemoryRecallToolInput: Equatable, Sendable {
    let characterCardId: String
    let query: String
    let limit: Int
}

protocol MemoryRecallProviding: Sendable {
    func recallMemories(
        for characterCardId: String,
        query: String,
        limit: Int
    ) async throws -> MemoryRecallResult
}

extension MemoryManager: MemoryRecallProviding {}

struct MemoryRecallTool: BackgroundSourceTool {
    private let provider: any MemoryRecallProviding

    let sourceType: BackgroundSourceType = .memory

    init(memoryManager: MemoryManager) {
        self.provider = memoryManager
    }

    init(provider: any MemoryRecallProviding) {
        self.provider = provider
    }

    func call(_ input: MemoryRecallToolInput) async throws -> MemoryRecallResult {
        try await provider.recallMemories(
            for: input.characterCardId,
            query: input.query,
            limit: input.limit
        )
    }
}
