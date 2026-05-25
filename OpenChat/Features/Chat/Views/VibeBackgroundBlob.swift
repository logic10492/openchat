import SwiftUI

struct VibeBackgroundBlob {
    let x: CGFloat
    let y: CGFloat
    let radius: CGFloat
    let seed: Double
    let speed: Double
    let hueIndex: Int

    static let all: [VibeBackgroundBlob] = [
        VibeBackgroundBlob(x: 0.20, y: 0.76, radius: 0.18, seed: 0.2, speed: 0.50, hueIndex: 0),
        VibeBackgroundBlob(x: 0.40, y: 0.82, radius: 0.22, seed: 1.6, speed: 0.34, hueIndex: 1),
        VibeBackgroundBlob(x: 0.62, y: 0.72, radius: 0.17, seed: 2.3, speed: 0.42, hueIndex: 2),
        VibeBackgroundBlob(x: 0.78, y: 0.84, radius: 0.19, seed: 3.1, speed: 0.38, hueIndex: 3),
        VibeBackgroundBlob(x: 0.28, y: 0.56, radius: 0.14, seed: 4.2, speed: 0.30, hueIndex: 4),
        VibeBackgroundBlob(x: 0.55, y: 0.47, radius: 0.13, seed: 5.0, speed: 0.35, hueIndex: 5),
        VibeBackgroundBlob(x: 0.72, y: 0.36, radius: 0.12, seed: 6.5, speed: 0.25, hueIndex: 6),
    ]
}
