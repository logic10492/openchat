import Foundation
import Testing

@testable import OpenChat

@Suite("Stage speaker block parser")
struct StageSpeakerBlockParserTests {
    @Test func test_parsesBracketSpeakerBlocks() {
        let blocks = StageSpeakerBlockParser().parse(
            """
            [Speaker: Mara]
            The gate is sealed.
            [/Speaker]
            [Speaker: Io]
            Then we wait.
            [/Speaker]
            """,
            participants: Self.participants()
        )

        #expect(blocks.map { $0.participant.displayName } == ["Mara", "Io"])
        #expect(blocks.map(\.content) == ["The gate is sealed.", "Then we wait."])
    }

    @Test func test_parsesNameColonBlocks() {
        let blocks = StageSpeakerBlockParser().parse(
            """
            Mara:
            Hold position.
            Io:
            Watching the north path.
            """,
            participants: Self.participants()
        )

        #expect(blocks.map { $0.participant.id } == ["participant-mara", "participant-io"])
        #expect(blocks.map(\.content) == ["Hold position.", "Watching the north path."])
    }

    @Test func test_unmarkedTextDoesNotSplit() {
        let blocks = StageSpeakerBlockParser().parse(
            "This is ordinary prose with no speaker marker.",
            participants: Self.participants()
        )

        #expect(blocks.isEmpty)
    }

    private static func participants() -> [StageParticipantRecord] {
        [
            StageParticipantRecord(
                id: "participant-mara",
                stageId: "stage-1",
                characterCardId: "card-mara",
                displayName: "Mara",
                visibility: StageParticipantVisibility.present.rawValue,
                isActive: true,
                sortOrder: 1,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            StageParticipantRecord(
                id: "participant-io",
                stageId: "stage-1",
                characterCardId: "card-io",
                displayName: "Io",
                visibility: StageParticipantVisibility.present.rawValue,
                isActive: true,
                sortOrder: 2,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
        ]
    }
}
