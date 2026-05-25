import CoreGraphics
import Foundation

struct VibeBackgroundDriver {
    private(set) var phase: VibeBackgroundPhase = .idle
    private(set) var flow: Double = 0.06
    private(set) var bandT: Double = 0
    private(set) var bandImpulse: Double = 0.18
    private(set) var pulse: Double = 0
    private(set) var particles: [VibeBackgroundParticle] = []

    private var randomSeed: UInt64 = 0x4d2c_6f91_8a73_b5e1

    mutating func setPhase(_ nextPhase: VibeBackgroundPhase, reduceMotion: Bool) {
        let didChangePhase = nextPhase != phase
        phase = nextPhase
        if didChangePhase {
            pulse = nextPhase == .idle ? min(pulse, 0.22) : 1
            bandImpulse = nextPhase == .idle ? 0.18 : nextPhase.impulse
        }

        if reduceMotion {
            flow = max(0.04, min(1, nextPhase.targetFlow * 0.85))
            particles.removeAll(keepingCapacity: true)
        }
    }

    mutating func update(
        deltaTime rawDeltaTime: TimeInterval,
        size: CGSize,
        palette: VibeBackgroundUIKitPalette,
        reduceMotion: Bool
    ) {
        let deltaTime = min(0.05, max(0.001, rawDeltaTime))

        if reduceMotion {
            particles.removeAll(keepingCapacity: true)
            return
        }

        let easing = phase == .streaming ? 0.04 : 0.025
        let targetFlow = min(1, phase.targetFlow * 0.998)
        flow = lerp(flow, targetFlow, easing)
        bandT += deltaTime * (palette.bandBaseSpeed + flow * palette.bandFlowSpeed + bandImpulse * palette.bandImpulseSpeed)
        bandImpulse = max(0, bandImpulse - deltaTime * 1.85)
        pulse = max(0, pulse - deltaTime * 0.85)

        spawnParticles(size: size, deltaTime: deltaTime, palette: palette)
        updateParticles(size: size, deltaTime: deltaTime)
    }

    private mutating func spawnParticles(
        size: CGSize,
        deltaTime: TimeInterval,
        palette: VibeBackgroundUIKitPalette
    ) {
        guard phase == .streaming else { return }
        let rate = 24 + 0.62 * 90
        let expectedCount = rate * deltaTime + nextRandom() * 1.4
        let count = Int(expectedCount)

        guard count > 0 else { return }

        for _ in 0..<count {
            particles.append(
                VibeBackgroundParticle(
                    x: CGFloat(nextRandom()) * size.width,
                    y: size.height * CGFloat(0.82 + nextRandom() * 0.16),
                    velocityX: CGFloat(nextRandom() - 0.5) * size.width * 0.035,
                    velocityY: -size.height * CGFloat(0.15 + nextRandom() * 0.36),
                    age: 0,
                    lifetime: 1.4 + nextRandom() * 1.9,
                    hue: palette.blobHues[Int(nextRandom() * 4).clamped(to: 0...3)],
                    radius: max(1, min(size.width, size.height) * CGFloat(0.004 + nextRandom() * 0.007))
                )
            )
        }
    }

    private mutating func updateParticles(size: CGSize, deltaTime: TimeInterval) {
        var retained: [VibeBackgroundParticle] = []
        retained.reserveCapacity(particles.count)

        for var particle in particles {
            particle.age += deltaTime
            particle.velocityY -= size.height * 0.08 * CGFloat(deltaTime)
            particle.x += (particle.velocityX + CGFloat(sin(bandT * 2 + particle.hue)) * 4) * CGFloat(deltaTime)
            particle.y += particle.velocityY * CGFloat(deltaTime)

            let life = 1 - particle.age / particle.lifetime
            if life > 0, particle.y >= size.height * 0.08 {
                retained.append(particle)
            }
        }

        particles = retained
    }

    private func lerp(_ lhs: Double, _ rhs: Double, _ amount: Double) -> Double {
        lhs + (rhs - lhs) * amount
    }

    private mutating func nextRandom() -> Double {
        randomSeed = randomSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let value = Double((randomSeed >> 11) & ((1 << 53) - 1))
        return value / Double(1 << 53)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
