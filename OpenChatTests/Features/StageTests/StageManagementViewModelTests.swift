import Foundation
import Testing

@testable import OpenChat

@MainActor
@Suite("Stage management view model")
struct StageManagementViewModelTests {
    @Test func test_loadStagesReadsStageParticipantsAndInstructions() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let appState = AppState()
        let conversation = TestHelpers.makeConversation(id: "stage-management-conversation", title: "Moonlit Stage")
        let card = TestHelpers.makeCharacterCard(id: "stage-management-card", name: "Mara")
        try await database.write { db in
            try card.insert(db)
            try conversation.insert(db)
        }
        let stage = try await database.createStage(
            conversationId: conversation.id,
            title: "Moonlit Stage",
            directorMode: .agent
        )
        _ = try await database.addStageParticipant(stageId: stage.id, characterCard: card)
        try await database.saveStageInstruction(
            StageInstructionRecord(
                id: "stage-management-instruction",
                stageId: stage.id,
                source: StageInstructionSource.user.rawValue,
                content: "Keep the reveal slow.",
                visibility: StageInstructionVisibility.hiddenFromCharacters.rawValue,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )

        let viewModel = StageManagementViewModel(databaseManager: database, appState: appState)
        await viewModel.loadStages()

        let item = try #require(viewModel.stages.first)
        #expect(item.stage.id == stage.id)
        #expect(item.conversation.title == "Moonlit Stage")
        #expect(item.participants.map(\.displayName) == ["Mara"])
        #expect(item.instructions.map(\.content) == ["Keep the reveal slow."])

        viewModel.openConversation(item)
        #expect(appState.selectedConversationID == conversation.id)
    }
}
