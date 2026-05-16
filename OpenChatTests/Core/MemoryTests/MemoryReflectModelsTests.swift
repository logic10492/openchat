import Foundation
import Testing

@testable import OpenChat

@Suite("Memory reflect contract")
struct MemoryReflectModelsTests {
    @Test func test_reflect_request_requires_source_memory_ids() throws {
        #expect(throws: MemoryReflectContractError.self) {
            _ = try MemoryReflectRequest(
                characterCardId: "card-1",
                task: .summarize,
                sourceMemoryIds: ["  "]
            )
        }
    }

    @Test func test_reflect_observation_requires_based_on_memory_ids() throws {
        #expect(throws: MemoryReflectContractError.self) {
            _ = try MemoryReflectObservation(
                content: "Ava links the lantern promise to the old map.",
                memoryType: .relationship,
                basedOnMemoryIds: [],
                suggestedAction: .insertObservation
            )
        }
    }

    @Test func test_reflect_observation_normalizes_content_and_confidence() throws {
        let observation = try MemoryReflectObservation(
            content: "  Ava connects the brass lantern to the rescue plan.  ",
            memoryType: .summary,
            basedOnMemoryIds: [" memory-a ", "memory-b"],
            confidence: 1.4,
            suggestedAction: .insertObservation
        )

        #expect(observation.content == "Ava connects the brass lantern to the rescue plan.")
        #expect(observation.basedOnMemoryIds == ["memory-a", "memory-b"])
        #expect(observation.confidence == 1.0)
        #expect(observation.suggestedAction == .insertObservation)
    }

    @Test func test_reflect_link_relations_are_minimal_supported_set() {
        let relations = Set(MemoryEntryLinkRelation.allCases.map(\.rawValue))

        #expect(relations == ["summarizes", "duplicates", "reinforces"])
    }

    @Test func test_reflect_tasks_and_actions_match_contract_values() {
        let tasks = Set(MemoryReflectTask.allCases.map(\.rawValue))
        let actions = Set(MemoryReflectAction.allCases.map(\.rawValue))

        #expect(tasks == ["summarize", "dedupe", "resolve_conflict", "relationship_observation"])
        #expect(actions == ["insert_observation", "mark_duplicate", "needs_user_review"])
    }
}
