import Foundation

enum LibrarianDraftTarget: String, Codable, Sendable, CaseIterable {
    case characterCard
    case worldBook
}

struct LibrarianSourceMaterial: Codable, Sendable, Equatable {
    let title: String
    let url: String?
    let excerpt: String
}

struct SourceCitation: Codable, Sendable, Equatable {
    let title: String
    let url: String?
    let excerpt: String?
}

struct CharacterCardPatch: Codable, Sendable, Equatable {
    let name: String?
    let personality: String?
    let appearance: String?
    let physique: String?
    let speechStyle: String?
    let backstory: String?
    let scenario: String?
    let exampleDialogs: [ChatMessage]
    let tags: [String]
    let creatorNotes: String?
}

struct WorldBookEntryDraft: Codable, Sendable, Equatable {
    let title: String
    let keywords: [String]
    let content: String
    let priority: Int
    let citations: [SourceCitation]
}

struct LibrarianDraft: Codable, Sendable, Equatable {
    let characterPatch: CharacterCardPatch?
    let worldBookEntries: [WorldBookEntryDraft]
    let citations: [SourceCitation]
    let warnings: [String]
}

struct LibrarianDraftRequest: Codable, Sendable, Equatable {
    let target: LibrarianDraftTarget
    let userGoal: String
    let sourceMaterials: [LibrarianSourceMaterial]
}

enum LibrarianDraftError: LocalizedError, Equatable, Sendable {
    case emptyGoal
    case emptyModelOutput
    case invalidJSON(String)
    case missingCitations
    case emptyDraft

    var errorDescription: String? {
        switch self {
        case .emptyGoal:
            "LibMan request must include a goal."
        case .emptyModelOutput:
            "LibMan output is empty."
        case .invalidJSON(let reason):
            "LibMan output is not valid JSON: \(reason)"
        case .missingCitations:
            "LibMan draft must include citations."
        case .emptyDraft:
            "LibMan draft must include a character patch or world book entries."
        }
    }
}

struct LibrarianDraftParser: Sendable {
    func parse(_ rawOutput: String) throws -> LibrarianDraft {
        let jsonString = try stripJSONFence(from: rawOutput)
        let data = Data(jsonString.utf8)

        do {
            let draft = try JSONDecoder().decode(LibrarianDraft.self, from: data)
            guard draft.characterPatch != nil || !draft.worldBookEntries.isEmpty else {
                throw LibrarianDraftError.emptyDraft
            }
            guard !draft.citations.isEmpty || draft.worldBookEntries.contains(where: { !$0.citations.isEmpty }) else {
                throw LibrarianDraftError.missingCitations
            }
            return draft
        } catch let error as LibrarianDraftError {
            throw error
        } catch {
            throw LibrarianDraftError.invalidJSON(error.localizedDescription)
        }
    }

    private func stripJSONFence(from rawOutput: String) throws -> String {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LibrarianDraftError.emptyModelOutput
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
            throw LibrarianDraftError.invalidJSON("Invalid JSON markdown fence.")
        }

        lines.removeFirst()
        lines.removeLast()
        let unfenced = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unfenced.isEmpty else {
            throw LibrarianDraftError.emptyModelOutput
        }
        return unfenced
    }
}

struct LibrarianDraftTask: AgentTask {
    let descriptor = AgentDescriptor(
        id: "background.librarian.draft",
        kind: .librarian,
        displayName: "LibMan",
        version: "1.0.0",
        purpose: "Create user-visible character card and world book drafts with citations."
    )
    let policy = AgentPolicy.librarianDraftOfflineDefault()

    private let apiClient: APIClient
    private let endpoint: APIEndpointConfig
    private let parser: LibrarianDraftParser

    init(
        apiClient: APIClient,
        endpoint: APIEndpointConfig,
        parser: LibrarianDraftParser = LibrarianDraftParser()
    ) {
        self.apiClient = apiClient
        self.endpoint = endpoint
        self.parser = parser
    }

    func run(
        input: LibrarianDraftRequest,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<LibrarianDraft> {
        guard !input.userGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibrarianDraftError.emptyGoal
        }

        let response = try await apiClient.sendMessage(
            messages: try makeMessages(input: input),
            endpoint: endpoint,
            parameters: Self.parameters
        )
        let rawOutput = response.choices.first?.message.content ?? ""
        let draft = try parser.parse(rawOutput)
        let tokenUsage = response.usage.map {
            AgentTokenUsage(
                inputTokens: $0.promptTokens,
                outputTokens: $0.completionTokens,
                totalTokens: $0.totalTokens
            )
        }
        let diagnostics = AgentDiagnostics.make(
            taskName: "librarianDraft",
            agent: descriptor,
            policy: policy,
            startedAt: context.now,
            endedAt: Date(),
            inputSummary: [
                "target": input.target.rawValue,
                "sourceCount": String(input.sourceMaterials.count),
            ],
            selectedIds: draft.citations.compactMap(\.url),
            tokenUsage: tokenUsage
        )
        return AgentExecutionResult(output: draft, diagnostics: diagnostics)
    }

    private func makeMessages(input: LibrarianDraftRequest) throws -> [ChatMessage] {
        let payload = LibrarianPromptPayload(
            target: input.target.rawValue,
            userGoal: input.userGoal,
            sourceMaterials: input.sourceMaterials
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let payloadText = String(decoding: data, as: UTF8.self)

        return [
            ChatMessage(
                role: "system",
                content: """
                You are OpenChat's LibMan. Create a user-visible draft only.
                Return ONLY one JSON object matching this schema:
                {
                  "characterPatch": {"name": null, "personality": null, "appearance": null, "physique": null, "speechStyle": null, "backstory": null, "scenario": null, "exampleDialogs": [], "tags": [], "creatorNotes": null},
                  "worldBookEntries": [{"title": "Entry", "keywords": ["term"], "content": "rewritten note", "priority": 50, "citations": [{"title": "Source", "url": "https://example.com", "excerpt": "short evidence"}]}],
                  "citations": [{"title": "Source", "url": "https://example.com", "excerpt": "short evidence"}],
                  "warnings": []
                }
                Do not write to any database. Do not draft live roleplay replies. Keep citations short.
                """
            ),
            ChatMessage(role: "user", content: payloadText),
        ]
    }

    private static let parameters = ModelParameters(
        temperature: 0.3,
        topP: 0.9,
        maxTokens: 1_200,
        frequencyPenalty: 0,
        presencePenalty: 0,
        stop: nil,
        thinkingBudget: nil,
        reasoningEffort: .high
    )
}

struct LibrarianDraftExecutor: Sendable {
    private let agentExecutor: any AgentExecutor
    private let apiClient: APIClient

    init(
        agentExecutor: any AgentExecutor = LLMAgentExecutor(),
        apiClient: APIClient
    ) {
        self.agentExecutor = agentExecutor
        self.apiClient = apiClient
    }

    func draft(
        request: LibrarianDraftRequest,
        endpoint: APIEndpointConfig,
        requestId: String = UUID().uuidString,
        now: Date = .now
    ) async throws -> AgentExecutionResult<LibrarianDraft> {
        let task = LibrarianDraftTask(apiClient: apiClient, endpoint: endpoint)
        return try await agentExecutor.execute(
            task: task,
            input: request,
            context: AgentExecutionContext(
                requestId: requestId,
                now: now,
                localeIdentifier: Locale.current.identifier
            )
        )
    }
}

private struct LibrarianPromptPayload: Encodable {
    let target: String
    let userGoal: String
    let sourceMaterials: [LibrarianSourceMaterial]
}
