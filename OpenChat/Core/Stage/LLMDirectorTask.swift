import Foundation

struct LLMDirectorTask: AgentTask {
    let descriptor = AgentDescriptor(
        id: "stage.director.llm",
        kind: .director,
        displayName: "Stage Director",
        version: "1.0.0",
        purpose: "Select stage speakers and hidden director instructions without drafting character dialogue."
    )
    let policy = AgentPolicy.directorDefault(allowsLLM: true)

    private let apiClient: APIClient
    private let endpoint: APIEndpointConfig
    private let parameters: ModelParameters
    private let fallbackPlan: StageTurnPlan

    init(
        apiClient: APIClient,
        endpoint: APIEndpointConfig,
        parameters: ModelParameters,
        fallbackPlan: StageTurnPlan
    ) {
        self.apiClient = apiClient
        self.endpoint = endpoint
        self.parameters = parameters
        self.fallbackPlan = fallbackPlan
    }

    func run(
        input: DirectorRuntimeInput,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<StageTurnPlan> {
        let startedAt = context.now
        let response = try await apiClient.sendMessage(
            messages: makeMessages(input: input),
            endpoint: endpoint,
            parameters: makeParameters()
        )
        let outputText = response.choices.first?.message.content ?? ""
        let decoded = Self.decodePlan(
            text: outputText,
            input: input,
            fallbackPlan: fallbackPlan,
            now: context.now
        )

        let tokenUsage = response.usage.map {
            AgentTokenUsage(
                inputTokens: $0.promptTokens,
                outputTokens: $0.completionTokens,
                totalTokens: $0.totalTokens
            )
        }
        let diagnostics = AgentDiagnostics.make(
            taskName: "llmDirectorPlan",
            agent: descriptor,
            policy: policy,
            startedAt: startedAt,
            endedAt: Date(),
            inputSummary: [
                "stageId": input.stageContext.stage.id,
                "participantCount": String(input.stageContext.activeParticipants.count),
                "mode": input.stageContext.stage.directorMode,
            ],
            selectedIds: decoded.selectedIds,
            fallbackReason: decoded.fallbackReason,
            tokenUsage: tokenUsage,
            schemaValidation: decoded.schemaValidation,
            errors: decoded.errors
        )

        var directorDiagnostics = decoded.plan.directorPlan.diagnostics
        directorDiagnostics = DirectorDiagnostics(
            warnings: directorDiagnostics.warnings + decoded.warnings,
            omittedInstructionIds: directorDiagnostics.omittedInstructionIds,
            policyProfile: directorDiagnostics.policyProfile.merging([
                "llm": decoded.usedFallback ? "false" : "true",
                "databaseWrite": "false",
                "toolUse": "disabled",
            ]) { current, _ in current },
            metadata: directorDiagnostics.metadata.merging([
                "runtime": decoded.usedFallback ? "llm-fallback" : "llm",
                "agentId": descriptor.id,
            ]) { _, new in new }
        )
        let directorPlan = DirectorPlan(
            mode: decoded.plan.directorPlan.mode,
            stageInstructions: decoded.plan.directorPlan.stageInstructions,
            speakerPlan: decoded.plan.directorPlan.speakerPlan,
            diagnostics: directorDiagnostics
        )
        let plan = StageTurnPlan(
            stage: decoded.plan.stage,
            participants: decoded.plan.participants,
            inputRole: decoded.plan.inputRole,
            participant: decoded.plan.participant,
            directorPlan: directorPlan,
            visibleInstructions: decoded.plan.visibleInstructions
        )
        return AgentExecutionResult(output: plan, diagnostics: diagnostics)
    }

    private func makeMessages(input: DirectorRuntimeInput) -> [ChatMessage] {
        [
            ChatMessage(
                role: "system",
                content: """
                You are OpenChat's Stage Director agent. Return only JSON. Do not draft character dialogue.
                Choose one participant for this turn and optional hidden director instructions.
                Schema:
                {
                  "speakerPlan": [{"participantId": "stage-participant-id", "intent": "respondToUser|react|advanceScene|remainSilent", "maxTokens": 180}],
                  "stageInstructions": [{"content": "hidden note", "visibility": "hiddenFromCharacters|visibleToParticipants|debugOnly"}],
                  "warnings": ["optional diagnostic"]
                }
                """
            ),
            ChatMessage(
                role: "user",
                content: makeUserPayload(input: input)
            ),
        ]
    }

    private func makeUserPayload(input: DirectorRuntimeInput) -> String {
        let participants = input.stageContext.activeParticipants.map {
            [
                "id": $0.id,
                "characterCardId": $0.characterCardId,
                "displayName": $0.displayName,
            ]
        }
        let instructions = input.stageContext.instructions.map {
            [
                "id": $0.id,
                "source": $0.source,
                "content": $0.content,
                "visibility": $0.visibility,
            ]
        }
        let payload: [String: Any] = [
            "stageId": input.stageContext.stage.id,
            "directorMode": input.stageContext.stage.directorMode,
            "inputRole": input.inputRole.rawValue,
            "currentInput": input.currentInput,
            "participants": participants,
            "existingInstructions": instructions,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return input.currentInput
        }
        return text
    }

    private func makeParameters() -> ModelParameters {
        var resolved = parameters
        resolved.temperature = min(parameters.temperature, 0.4)
        resolved.topP = min(parameters.topP, 0.9)
        resolved.maxTokens = min(parameters.maxTokens ?? 600, 600)
        resolved.stop = nil
        resolved.thinkingBudget = nil
        return resolved
    }
}

private extension LLMDirectorTask {
    struct DecodedPlan {
        let plan: StageTurnPlan
        let schemaValidation: SchemaValidationResult
        let selectedIds: [String]
        let fallbackReason: String?
        let warnings: [String]
        let errors: [AgentDiagnosticError]
        let usedFallback: Bool
    }

    struct Payload: Decodable {
        let speakerPlan: [Speaker]?
        let stageInstructions: [Instruction]?
        let warnings: [String]?
    }

    struct Speaker: Decodable {
        let participantId: String?
        let characterCardId: String?
        let intent: SpeakerTurnIntent?
        let maxTokens: Int?
    }

    struct Instruction: Decodable {
        let content: String
        let visibility: StageInstructionVisibility?
    }

    static func decodePlan(
        text: String,
        input: DirectorRuntimeInput,
        fallbackPlan: StageTurnPlan,
        now: Date
    ) -> DecodedPlan {
        guard let jsonText = extractJSONObject(from: text),
              let data = jsonText.data(using: .utf8)
        else {
            return fallback(
                plan: fallbackPlan,
                reason: "missing-json-object",
                message: "LLM director output did not contain a JSON object."
            )
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return fallback(
                plan: fallbackPlan,
                reason: "decode-failed",
                message: error.localizedDescription
            )
        }

        let activeParticipants = input.stageContext.activeParticipants
        let firstSpeaker = payload.speakerPlan?.first
        let participant = resolveParticipant(from: firstSpeaker, participants: activeParticipants)
            ?? fallbackPlan.participant

        guard let participant else {
            return fallback(
                plan: fallbackPlan,
                reason: "participant-unresolved",
                message: "LLM director did not resolve a valid participant."
            )
        }

        let instructions = makeInstructions(payload.stageInstructions ?? [], now: now)
        let visibleInstructions = fallbackPlan.visibleInstructions + instructions
        let speakerTurn = SpeakerTurn(
            participantId: participant.id,
            characterCardId: participant.characterCardId,
            intent: firstSpeaker?.intent ?? .respondToUser,
            maxTokens: firstSpeaker?.maxTokens
        )
        let diagnostics = DirectorDiagnostics(
            warnings: payload.warnings ?? [],
            omittedInstructionIds: [],
            policyProfile: [
                "mode": DirectorMode.agent.rawValue,
                "llm": "true",
                "databaseWrite": "false",
            ],
            metadata: [
                "runtime": "llm",
                "participantId": participant.id,
            ]
        )
        let directorPlan = DirectorPlan(
            mode: .agent,
            stageInstructions: visibleInstructions,
            speakerPlan: [speakerTurn],
            diagnostics: diagnostics
        )
        let plan = StageTurnPlan(
            stage: input.stageContext.stage,
            participants: activeParticipants,
            inputRole: input.inputRole,
            participant: participant,
            directorPlan: directorPlan,
            visibleInstructions: visibleInstructions
        )
        return DecodedPlan(
            plan: plan,
            schemaValidation: SchemaValidationResult(isValid: true, repaired: false, errors: []),
            selectedIds: [participant.id],
            fallbackReason: nil,
            warnings: payload.warnings ?? [],
            errors: [],
            usedFallback: false
        )
    }

    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        return String(text[start...end])
    }

    static func resolveParticipant(
        from speaker: Speaker?,
        participants: [StageParticipantRecord]
    ) -> StageParticipantRecord? {
        guard let speaker else { return participants.first }
        if let id = speaker.participantId,
           let participant = participants.first(where: { $0.id == id }) {
            return participant
        }
        if let cardId = speaker.characterCardId,
           let participant = participants.first(where: { $0.characterCardId == cardId }) {
            return participant
        }
        return nil
    }

    static func makeInstructions(
        _ payload: [Instruction],
        now: Date
    ) -> [StageInstruction] {
        payload.compactMap { instruction in
            try? StageInstruction(
                id: UUID().uuidString,
                source: .directorAgent,
                content: instruction.content,
                visibility: instruction.visibility ?? .hiddenFromCharacters,
                createdAt: now
            )
        }
    }

    static func fallback(
        plan: StageTurnPlan,
        reason: String,
        message: String
    ) -> DecodedPlan {
        let diagnostics = DirectorDiagnostics(
            warnings: plan.directorPlan.diagnostics.warnings + [message],
            omittedInstructionIds: plan.directorPlan.diagnostics.omittedInstructionIds,
            policyProfile: plan.directorPlan.diagnostics.policyProfile.merging([
                "llm": "false",
                "databaseWrite": "false",
            ]) { current, _ in current },
            metadata: plan.directorPlan.diagnostics.metadata.merging([
                "runtime": "llm-fallback",
                "fallbackReason": reason,
            ]) { current, _ in current }
        )
        let directorPlan = DirectorPlan(
            mode: plan.directorPlan.mode,
            stageInstructions: plan.directorPlan.stageInstructions,
            speakerPlan: plan.directorPlan.speakerPlan,
            diagnostics: diagnostics
        )
        let fallbackPlan = StageTurnPlan(
            stage: plan.stage,
            participants: plan.participants,
            inputRole: plan.inputRole,
            participant: plan.participant,
            directorPlan: directorPlan,
            visibleInstructions: plan.visibleInstructions
        )
        return DecodedPlan(
            plan: fallbackPlan,
            schemaValidation: SchemaValidationResult(isValid: false, repaired: true, errors: [message]),
            selectedIds: plan.participant.map { [$0.id] } ?? [],
            fallbackReason: reason,
            warnings: [message],
            errors: [AgentDiagnosticError(code: reason, message: message)],
            usedFallback: true
        )
    }
}
