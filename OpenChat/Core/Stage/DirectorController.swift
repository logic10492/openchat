import Foundation

struct DirectorController: Sendable {
    func planTurn(
        stageContext: StageContext,
        inputRole: StageInputRole,
        currentInput: String,
        now: Date = .now
    ) throws -> StageTurnPlan {
        let visibleInstructions = stageContext.instructions.compactMap(\.stageInstruction)
        let newInstruction: StageInstruction?
        if inputRole.isDirectorInstructionInput {
            newInstruction = try StageInstruction.userDirected(
                id: UUID().uuidString,
                content: currentInput,
                createdAt: now
            )
        } else {
            newInstruction = nil
        }

        let allInstructions = visibleInstructions + [newInstruction].compactMap { $0 }
        let participant = chooseParticipant(
            from: stageContext.activeParticipants,
            currentInput: currentInput
        )

        if !inputRole.isDirectorInstructionInput, participant == nil {
            throw StageError.participantMissing
        }

        let speakerPlan = participant.map {
            SpeakerTurn(
                participantId: $0.id,
                characterCardId: $0.characterCardId,
                intent: inputRole.isDirectorInstructionInput ? .remainSilent : .respondToUser,
                maxTokens: nil
            )
        }.map { [$0] } ?? []

        let diagnostics = DirectorDiagnostics(
            warnings: inputRole.isDirectorInstructionInput ? ["director input stored as stage instruction"] : [],
            omittedInstructionIds: [],
            policyProfile: [
                "mode": stageContext.stage.directorMode,
                "llm": "false",
                "databaseWrite": "false",
            ],
            metadata: [
                "runtime": "deterministic",
                "participants": String(stageContext.activeParticipants.count),
            ]
        )

        let plan = DirectorPlan(
            mode: stageContext.stage.directorModeValue,
            stageInstructions: allInstructions,
            speakerPlan: speakerPlan,
            diagnostics: diagnostics
        )

        return StageTurnPlan(
            stage: stageContext.stage,
            participants: stageContext.activeParticipants,
            inputRole: inputRole,
            participant: participant,
            directorPlan: plan,
            visibleInstructions: allInstructions
        )
    }

    private func chooseParticipant(
        from participants: [StageParticipantRecord],
        currentInput: String
    ) -> StageParticipantRecord? {
        if let mentioned = participants.first(where: { participant in
            currentInput.localizedCaseInsensitiveContains(participant.displayName)
        }) {
            return mentioned
        }
        return participants.first
    }
}
