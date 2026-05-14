import Foundation

enum MemoryExtractionPhase: Sendable, Equatable {
    case idle
    case extracting
    case completed(count: Int, summaries: [String])
    case skipped
    case failed(description: String)

    var isActive: Bool {
        switch self {
        case .extracting, .completed, .failed:
            true
        case .idle, .skipped:
            false
        }
    }
}
