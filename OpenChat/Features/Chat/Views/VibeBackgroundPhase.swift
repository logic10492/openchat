import SwiftUI

enum VibeBackgroundPhase: Equatable {
    case idle
    case waiting
    case streaming
    case completing

    var targetFlow: Double {
        switch self {
        case .idle:
            0.06
        case .waiting:
            0.36
        case .streaming:
            1.0
        case .completing:
            0.18
        }
    }

    var impulse: Double {
        switch self {
        case .idle:
            0.08
        case .waiting:
            0.26
        case .streaming:
            0.86
        case .completing:
            0.22
        }
    }

    var flowResponse: Double {
        switch self {
        case .idle:
            0.36
        case .waiting:
            0.42
        case .streaming:
            0.78
        case .completing:
            0.48
        }
    }

    var impulseResponse: Double {
        switch self {
        case .idle:
            0.32
        case .waiting:
            0.72
        case .streaming:
            1.15
        case .completing:
            0.62
        }
    }

    var washStrength: Double {
        switch self {
        case .idle:
            0
        case .waiting:
            0.40
        case .streaming:
            0.26
        case .completing:
            0.12
        }
    }

    var washCenterY: CGFloat {
        switch self {
        case .idle:
            0.84
        case .waiting:
            0.72
        case .streaming, .completing:
            0.84
        }
    }

    var frameInterval: TimeInterval {
        switch self {
        case .idle:
            1.0 / 18.0
        case .waiting:
            1.0 / 20.0
        case .streaming:
            1.0 / 30.0
        case .completing:
            1.0 / 18.0
        }
    }
}
