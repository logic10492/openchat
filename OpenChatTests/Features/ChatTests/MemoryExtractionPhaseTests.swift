import Foundation
import Testing

@testable import OpenChat

@Suite("MemoryExtractionPhase")
struct MemoryExtractionPhaseTests {
    @Test func test_idle_is_not_active() {
        #expect(!MemoryExtractionPhase.idle.isActive)
    }

    @Test func test_skipped_is_not_active() {
        #expect(!MemoryExtractionPhase.skipped.isActive)
    }

    @Test func test_extracting_is_active() {
        #expect(MemoryExtractionPhase.extracting.isActive)
    }

    @Test func test_completed_is_active() {
        let phase = MemoryExtractionPhase.completed(count: 3, summaries: ["a", "b", "c"])
        #expect(phase.isActive)
    }

    @Test func test_failed_is_active() {
        let phase = MemoryExtractionPhase.failed(description: "Network error")
        #expect(phase.isActive)
    }

    @Test func test_equatable_idle() {
        #expect(MemoryExtractionPhase.idle == .idle)
    }

    @Test func test_equatable_completed_same_values() {
        let a = MemoryExtractionPhase.completed(count: 2, summaries: ["x"])
        let b = MemoryExtractionPhase.completed(count: 2, summaries: ["x"])
        #expect(a == b)
    }

    @Test func test_equatable_completed_different_values() {
        let a = MemoryExtractionPhase.completed(count: 2, summaries: ["x"])
        let b = MemoryExtractionPhase.completed(count: 3, summaries: ["x", "y", "z"])
        #expect(a != b)
    }
}
