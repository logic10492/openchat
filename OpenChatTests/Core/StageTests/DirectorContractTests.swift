import Foundation
import Testing

@testable import OpenChat

@Suite("Director contract DTOs")
struct DirectorContractTests {
    @Test func test_directorModeRawValues_areStable() {
        #expect(DirectorMode.silent.rawValue == "silent")
        #expect(DirectorMode.agent.rawValue == "agent")
        #expect(DirectorMode.userControlled.rawValue == "userControlled")
        #expect(DirectorMode.allCases == [.silent, .agent, .userControlled])
    }

    @Test func test_stageInputRoleRawValues_areInputSemanticsNotChatRoles() {
        #expect(StageInputRole.participant.rawValue == "participant")
        #expect(StageInputRole.director.rawValue == "director")
        #expect(StageInputRole.director.rawValue != "user")
        #expect(StageInputRole.participant.rawValue != "assistant")
        #expect(!StageInputRole.participant.isDirectorInstructionInput)
        #expect(StageInputRole.director.isDirectorInstructionInput)
    }

    @Test func test_silentPlan_canBeEmpty() {
        let plan = DirectorPlan(mode: .silent)

        #expect(plan.mode == .silent)
        #expect(plan.stageInstructions.isEmpty)
        #expect(plan.speakerPlan.isEmpty)
        #expect(plan.diagnostics == .empty)
    }

    @Test func test_stageInstruction_trimsContentAndDefaultsToHiddenVisibility() throws {
        let createdAt = Date(timeIntervalSince1970: 1)
        let instruction = try StageInstruction.userDirected(
            id: "instruction-1",
            content: "  Hold the reveal for one more beat.  ",
            createdAt: createdAt
        )

        #expect(instruction.id == "instruction-1")
        #expect(instruction.source == .user)
        #expect(instruction.content == "Hold the reveal for one more beat.")
        #expect(instruction.visibility == .hiddenFromCharacters)
        #expect(instruction.createdAt == createdAt)
    }

    @Test func test_stageInstructionRejectsEmptyContent() {
        #expect(throws: StageInstructionError.emptyContent) {
            try StageInstruction.userDirected(
                id: "empty",
                content: " \n\t ",
                createdAt: Date(timeIntervalSince1970: 1)
            )
        }
    }

    @Test func test_userControlledDirectorInput_encodesAsStageInstructionBoundary() throws {
        let input = DirectorInput(
            mode: .userControlled,
            userInputRole: .director,
            currentInput: "Let Mara stay silent this turn.",
            recentInstructionIds: ["previous-instruction"]
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(DirectorInput.self, from: data)

        #expect(decoded == input)
        #expect(decoded.userInputRole == .director)
        #expect(decoded.userInputRole.isDirectorInstructionInput)
    }

    @Test func test_directorPlan_roundTripsWithoutAssistantMessageContent() throws {
        let instruction = try StageInstruction(
            id: "director-agent-1",
            source: .directorAgent,
            content: "Escalate tension without resolving the conflict.",
            visibility: .debugOnly,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let turn = SpeakerTurn(
            participantId: "participant-a",
            characterCardId: nil,
            intent: .advanceScene,
            maxTokens: 180
        )
        let diagnostics = DirectorDiagnostics(
            warnings: ["speaker hint unresolved"],
            omittedInstructionIds: ["stale-instruction"],
            policyProfile: ["llm": "false"],
            metadata: ["source": "deterministic"]
        )
        let plan = DirectorPlan(
            mode: .agent,
            stageInstructions: [instruction],
            speakerPlan: [turn],
            diagnostics: diagnostics
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        let decoded = try JSONDecoder().decode(DirectorPlan.self, from: data)
        let encodedText = String(decoding: data, as: UTF8.self)

        #expect(decoded == plan)
        #expect(!encodedText.contains("assistant"))
        #expect(!encodedText.contains("message"))
    }

    @Test func test_directorDiagnostics_roundTripsWithoutUserVisibleDraftFields() throws {
        let diagnostics = DirectorDiagnostics(
            warnings: ["instruction omitted"],
            omittedInstructionIds: ["instruction-2"],
            policyProfile: ["network": "denied"],
            metadata: ["mode": "agent"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(diagnostics)
        let decoded = try JSONDecoder().decode(DirectorDiagnostics.self, from: data)
        let encodedText = String(decoding: data, as: UTF8.self)

        #expect(decoded == diagnostics)
        #expect(!encodedText.contains("assistant"))
        #expect(!encodedText.contains("draft"))
        #expect(!encodedText.contains("messageRole"))
    }

    @Test func test_stagePromptLayerPlan_placesDirectorInstructionsBeforeCurrentTurn() {
        let layers = StagePromptLayerPlan.defaultLayerOrder

        #expect(layers.first == .stageIdentity)
        #expect(layers.last == .currentTurn)
        #expect(index(of: .currentBackground, in: layers) < index(of: .directorInstructions, in: layers))
        #expect(index(of: .directorInstructions, in: layers) < index(of: .currentTurn, in: layers))
    }

    @Test func test_speakerTurn_isOnlyAHintAndDoesNotRequireResolvedParticipant() {
        let turn = SpeakerTurn(intent: .remainSilent)

        #expect(turn.participantId == nil)
        #expect(turn.characterCardId == nil)
        #expect(turn.intent == .remainSilent)
        #expect(turn.maxTokens == nil)
    }
}

private func index(of layer: StagePromptLayer, in layers: [StagePromptLayer]) -> Int {
    guard let index = layers.firstIndex(of: layer) else {
        Issue.record("Missing prompt layer: \(layer.rawValue)")
        return Int.max
    }

    return index
}
