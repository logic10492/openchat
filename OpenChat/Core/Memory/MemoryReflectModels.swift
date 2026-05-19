import Foundation

struct MemoryReflectRequest: Sendable {
    let characterCardId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]

    init(
        characterCardId: String,
        task: MemoryReflectTask,
        sourceMemoryIds: [String]
    ) throws {
        let trimmedCharacterCardId = characterCardId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceIds = sourceMemoryIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedCharacterCardId.isEmpty else {
            throw MemoryReflectContractError.emptyCharacterCardId
        }
        guard !normalizedSourceIds.isEmpty else {
            throw MemoryReflectContractError.emptySourceMemoryIds
        }

        self.characterCardId = trimmedCharacterCardId
        self.task = task
        self.sourceMemoryIds = normalizedSourceIds
    }
}

struct MemoryReflectObservation: Sendable {
    let content: String
    let memoryType: MemoryType
    let basedOnMemoryIds: [String]
    let confidence: Double?
    let suggestedAction: MemoryReflectAction

    init(
        content: String,
        memoryType: MemoryType,
        basedOnMemoryIds: [String],
        confidence: Double? = nil,
        suggestedAction: MemoryReflectAction
    ) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBasedOnIds = basedOnMemoryIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedContent.isEmpty else {
            throw MemoryReflectContractError.emptyObservationContent
        }
        guard !normalizedBasedOnIds.isEmpty else {
            throw MemoryReflectContractError.emptyBasedOnMemoryIds
        }

        self.content = trimmedContent
        self.memoryType = memoryType
        self.basedOnMemoryIds = normalizedBasedOnIds
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.suggestedAction = suggestedAction
    }
}

enum MemoryReflectTask: String, Codable, CaseIterable, Sendable {
    case summarize
    case dedupe
    case resolveConflict = "resolve_conflict"
    case relationshipObservation = "relationship_observation"
}

enum MemoryReflectAction: String, Codable, CaseIterable, Sendable {
    case insertObservation = "insert_observation"
    case markDuplicate = "mark_duplicate"
    case needsUserReview = "needs_user_review"
}

enum MemoryEntryLinkRelation: String, Codable, CaseIterable, Sendable {
    case summarizes
    case duplicates
    case reinforces
}

enum MemoryReflectContractError: LocalizedError, Equatable, Sendable {
    case emptyCharacterCardId
    case emptySourceMemoryIds
    case emptyObservationContent
    case emptyBasedOnMemoryIds

    var errorDescription: String? {
        switch self {
        case .emptyCharacterCardId:
            "Memory reflect request must include a character card id."
        case .emptySourceMemoryIds:
            "Memory reflect request must include source memory ids."
        case .emptyObservationContent:
            "Memory reflect observation must include content."
        case .emptyBasedOnMemoryIds:
            "Memory reflect observation must include based-on memory ids."
        }
    }
}

struct MemoryReflectPromptBuilder: Sendable {
    func buildMessages(request: MemoryReflectRequest, sourceMemories: [MemoryEntryRecord]) throws -> [ChatMessage] {
        let payload = MemoryReflectPromptPayload(
            characterCardId: request.characterCardId,
            task: request.task.rawValue,
            sourceMemories: sourceMemories.map { memory in
                MemoryReflectPromptPayload.SourceMemory(
                    id: memory.id,
                    type: memory.memoryType,
                    content: memory.content
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let payloadString: String
        do {
            payloadString = String(decoding: try encoder.encode(payload), as: UTF8.self)
        } catch {
            throw MemoryReflectError.promptEncodingFailed(error.localizedDescription)
        }

        return [
            ChatMessage(
                role: "system",
                content: """
                You synthesize long-term memory observations from the provided source memories.
                Return ONLY one JSON object with keys content, type, basedOn, confidence, and suggestedAction.
                Do not return markdown, an array, multiple observations, or explanatory text.
                """
            ),
            ChatMessage(role: "user", content: payloadString),
        ]
    }
}

struct MemoryReflectParser: Sendable {
    func parse(_ rawOutput: String, sourceMemoryIds: [String]) throws -> MemoryReflectObservation {
        let jsonString = try stripJSONFence(from: rawOutput)
        let data = Data(jsonString.utf8)
        let json: Any

        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MemoryReflectError.invalidJSON(error.localizedDescription)
        }

        if let array = json as? [Any] {
            throw array.count == 1
                ? MemoryReflectError.expectedSingleJSONObject
                : MemoryReflectError.multipleObservationsNotSupported
        }

        guard let object = json as? [String: Any] else {
            throw MemoryReflectError.expectedSingleJSONObject
        }

        try rejectNestedObservations(in: object)

        guard let rawContent = object["content"] as? String,
              !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MemoryReflectError.missingContent
        }

        let basedOn = try parseBasedOn(from: object)
        let allowedIds = Set(sourceMemoryIds)
        let unknownIds = basedOn.filter { !allowedIds.contains($0) }
        guard unknownIds.isEmpty else {
            throw MemoryReflectError.unknownBasedOnIds(unknownIds)
        }

        guard let rawType = object["type"] as? String else {
            throw MemoryReflectError.missingMemoryType
        }
        guard let memoryType = MemoryType(rawValue: rawType) else {
            throw MemoryReflectError.invalidMemoryType(rawType)
        }

        guard let rawAction = object["suggestedAction"] as? String else {
            throw MemoryReflectError.missingSuggestedAction
        }
        guard let suggestedAction = MemoryReflectAction(rawValue: rawAction) else {
            throw MemoryReflectError.invalidSuggestedAction(rawAction)
        }

        let confidence = try parseConfidence(from: object)

        return try MemoryReflectObservation(
            content: rawContent,
            memoryType: memoryType,
            basedOnMemoryIds: basedOn,
            confidence: confidence,
            suggestedAction: suggestedAction
        )
    }

    private func stripJSONFence(from rawOutput: String) throws -> String {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MemoryReflectError.emptyModelOutput
        }

        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        var lines = trimmed.components(separatedBy: .newlines)
        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("```json") ||
                  firstLine.trimmingCharacters(in: .whitespacesAndNewlines) == "```",
              let lastLine = lines.last,
              lastLine.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            throw MemoryReflectError.invalidJSON("Invalid JSON markdown fence.")
        }

        lines.removeFirst()
        lines.removeLast()
        let unfenced = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unfenced.isEmpty else {
            throw MemoryReflectError.emptyModelOutput
        }
        return unfenced
    }

    private func rejectNestedObservations(in object: [String: Any]) throws {
        for key in ["observations", "items", "results"] where object[key] is [Any] {
            throw MemoryReflectError.multipleObservationsNotSupported
        }
    }

    private func parseBasedOn(from object: [String: Any]) throws -> [String] {
        guard let value = object["basedOn"] else {
            throw MemoryReflectError.missingBasedOn
        }
        guard let rawIds = value as? [Any] else {
            throw MemoryReflectError.invalidBasedOn
        }

        let ids = try rawIds.map { value -> String in
            guard let id = value as? String else {
                throw MemoryReflectError.invalidBasedOn
            }
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        guard !ids.isEmpty else {
            throw MemoryReflectError.missingBasedOn
        }
        return ids
    }

    private func parseConfidence(from object: [String: Any]) throws -> Double? {
        guard let value = object["confidence"], !(value is NSNull) else {
            return nil
        }
        if value is Bool {
            throw MemoryReflectError.invalidConfidence
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        throw MemoryReflectError.invalidConfidence
    }
}

struct MemoryReflectResult: Sendable {
    let observation: MemoryReflectObservation
    let diagnostics: MemoryReflectDiagnostics
}

struct MemoryReflectDiagnostics: Equatable, Sendable {
    let requestId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]
    let modelId: String
    let inputMessageCount: Int
    let parseRepairCount: Int
    let rejectedReason: String?
}

struct MemoryReflectExecutor: Sendable {
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient
    private let promptBuilder: MemoryReflectPromptBuilder
    private let parser: MemoryReflectParser

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        promptBuilder: MemoryReflectPromptBuilder = MemoryReflectPromptBuilder(),
        parser: MemoryReflectParser = MemoryReflectParser()
    ) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.promptBuilder = promptBuilder
        self.parser = parser
    }

    func reflect(
        request: MemoryReflectRequest,
        endpoint: APIEndpointConfig,
        requestId: String = UUID().uuidString
    ) async throws -> MemoryReflectResult {
        let sourceMemories = try await fetchOrderedSourceMemories(for: request)
        let messages = try promptBuilder.buildMessages(request: request, sourceMemories: sourceMemories)
        let diagnostics = MemoryReflectDiagnostics(
            requestId: requestId,
            task: request.task,
            sourceMemoryIds: request.sourceMemoryIds,
            modelId: endpoint.modelName,
            inputMessageCount: messages.count,
            parseRepairCount: 0,
            rejectedReason: nil
        )

        let response = try await apiClient.sendMessage(
            messages: messages,
            endpoint: endpoint,
            parameters: Self.conservativeParameters
        )

        guard let rawOutput = response.choices.first?.message.content,
              !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MemoryReflectError.emptyAPIResponse
        }

        do {
            let observation = try parser.parse(rawOutput, sourceMemoryIds: request.sourceMemoryIds)
            return MemoryReflectResult(observation: observation, diagnostics: diagnostics)
        } catch let error as MemoryReflectError {
            let failedDiagnostics = MemoryReflectDiagnostics(
                requestId: requestId,
                task: request.task,
                sourceMemoryIds: request.sourceMemoryIds,
                modelId: endpoint.modelName,
                inputMessageCount: messages.count,
                parseRepairCount: 0,
                rejectedReason: error.localizedDescription
            )
            throw MemoryReflectExecutorError(error: error, diagnostics: failedDiagnostics)
        }
    }

    private func fetchOrderedSourceMemories(for request: MemoryReflectRequest) async throws -> [MemoryEntryRecord] {
        let fetched = try await databaseManager.fetchMemories(ids: request.sourceMemoryIds)
        let byId = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        let missingIds = request.sourceMemoryIds.filter { byId[$0] == nil }
        guard missingIds.isEmpty else {
            throw MemoryReflectError.missingSourceMemories(missingIds)
        }

        let orderedMemories = request.sourceMemoryIds.compactMap { byId[$0] }
        for memory in orderedMemories where memory.characterCardId != request.characterCardId {
            throw MemoryReflectError.crossCharacterMemory(
                id: memory.id,
                expectedCharacterCardId: request.characterCardId,
                actualCharacterCardId: memory.characterCardId
            )
        }
        return orderedMemories
    }

    private static let conservativeParameters = ModelParameters(
        temperature: 0.2,
        topP: 0.9,
        maxTokens: 700,
        frequencyPenalty: 0,
        presencePenalty: 0,
        stop: nil,
        thinkingBudget: nil,
        reasoningEffort: .high
    )
}

struct MemoryReflectExecutorError: LocalizedError, Equatable, Sendable {
    let error: MemoryReflectError
    let diagnostics: MemoryReflectDiagnostics

    var errorDescription: String? {
        error.localizedDescription
    }
}

private struct MemoryReflectPromptPayload: Encodable {
    let characterCardId: String
    let task: String
    let sourceMemories: [SourceMemory]

    struct SourceMemory: Encodable {
        let id: String
        let type: String
        let content: String
    }
}
