import SwiftUI

struct VibeBackgroundCanvas: View {
    let phase: VibeBackgroundPhase
    let phaseStartedAt: Date
    let date: Date
    let palette: VibeBackgroundPalette
    let reduceMotion: Bool

    private let defaultFlow: Double = 0.58
    private let defaultParticleAmount: Double = 0.62

    var body: some View {
        Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: false) { context, size in
            let time = date.timeIntervalSinceReferenceDate
            let phaseElapsed = max(0, date.timeIntervalSince(phaseStartedAt))
            let flow = flowValue(phaseElapsed: phaseElapsed)
            drawBase(context: &context, size: size)
            drawBands(context: &context, size: size, time: time, phaseElapsed: phaseElapsed, flow: flow)
            drawBlobs(context: &context, size: size, time: time, flow: flow)
            drawPhaseWash(context: &context, size: size, phaseElapsed: phaseElapsed)
            if phase == .streaming, !reduceMotion {
                drawParticles(context: &context, size: size, time: time)
            }
        }
    }

    private func flowValue(phaseElapsed: TimeInterval) -> Double {
        let target = phase.targetFlow * (0.65 + 0.60 * defaultFlow)
        let eased = 1 - exp(-phaseElapsed * phase.flowResponse)
        return max(0.04, min(1, target * eased + 0.06 * (1 - eased)))
    }

    private func drawBase(context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: palette.baseColors),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    private func drawBands(
        context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        phaseElapsed: TimeInterval,
        flow: Double
    ) {
        var bandContext = context
        bandContext.blendMode = palette.blendMode
        let impulse = phase.impulse * (1 - exp(-phaseElapsed * phase.impulseResponse))
        let bandT = time * (palette.bandBaseSpeed + flow * palette.bandFlowSpeed) + impulse * palette.bandImpulseSpeed

        for index in 0..<palette.bandHues.count {
            let yBase = size.height * (0.12 + CGFloat(index) * 0.095 + CGFloat(flow) * 0.06)
            let lateral = sin(bandT * (0.72 + Double(index) * 0.05) + Double(index) * 1.7)
                * size.width
                * (0.045 + CGFloat(flow) * 0.13)
            let diagonal = (CGFloat(index) - 3) * size.width * 0.018 * CGFloat(flow)
            var path = Path()
            path.move(to: CGPoint(x: -size.width * 0.24 + lateral, y: yBase))

            for step in 0...10 {
                let progress = CGFloat(step) / 10
                let x = progress * size.width * 1.48 - size.width * 0.22 + lateral + diagonal * progress
                let y = yBase + wave(
                    seed: Double(index) * 1.7 + Double(step),
                    time: time * (0.34 + flow * 0.28),
                    amplitude: size.height * (0.04 + CGFloat(flow) * 0.06)
                )
                path.addLine(to: CGPoint(x: x, y: y))
            }

            bandContext.stroke(
                path,
                with: .color(
                    palette.color(
                        hue: palette.bandHues[index] + flow * 46,
                        alpha: (0.075 + flow * 0.16) * palette.alphaScale
                    )
                ),
                style: StrokeStyle(
                    lineWidth: size.height * (0.07 + CGFloat(flow) * 0.052),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func drawBlobs(context: inout GraphicsContext, size: CGSize, time: TimeInterval, flow: Double) {
        var blobContext = context
        blobContext.blendMode = palette.blendMode

        for blob in VibeBackgroundBlob.all {
            let hue = palette.blobHues[blob.hueIndex]
            let driftX = wave(seed: blob.seed, time: time * blob.speed, amplitude: 0.035)
            let driftY = wave(seed: blob.seed + 4.5, time: time * blob.speed * 0.8, amplitude: 0.03)
            let x = (blob.x + driftX + CGFloat(flow) * wave(seed: blob.seed + 9, time: time * 0.25, amplitude: 0.05)) * size.width
            let y = (blob.y + driftY - CGFloat(flow) * blob.y * 0.18) * size.height
            let radius = blob.radius * min(size.width, size.height) * (1 + wave(seed: blob.seed + 8, time: time * 0.62, amplitude: 0.12))

            if flow > 0.28 {
                drawStreamTail(
                    context: &blobContext,
                    hue: hue,
                    origin: CGPoint(x: x, y: y),
                    radius: radius,
                    seed: blob.seed,
                    time: time,
                    flow: flow
                )
            }

            fillRadial(
                context: &blobContext,
                center: CGPoint(x: x, y: y),
                radius: radius * (1.2 + CGFloat(flow) * 0.45),
                stops: [
                    (0.00, palette.color(hue: hue, alpha: (0.44 - flow * 0.12) * palette.alphaScale)),
                    (0.48, palette.color(hue: hue + 28, alpha: 0.24 * palette.alphaScale)),
                    (1.00, palette.color(hue: hue + 74, alpha: 0)),
                ]
            )
        }
    }

    private func drawStreamTail(
        context: inout GraphicsContext,
        hue: Double,
        origin: CGPoint,
        radius: CGFloat,
        seed: Double,
        time: TimeInterval,
        flow: Double
    ) {
        let streamLength = radius * (2.4 + CGFloat(flow) * 4.0)
        for index in 0..<9 {
            let progress = CGFloat(index) / 8
            let sway = sin(time * 0.92 + seed * 3 + Double(progress) * 4) * radius * 0.45 * CGFloat(flow)
            let center = CGPoint(
                x: origin.x + sway + (progress - 0.5) * radius * 0.35,
                y: origin.y - progress * streamLength
            )
            let segmentRadius = radius * (0.72 + (0.28 - 0.72) * progress) * (1 - 0.25 * CGFloat(flow))
            fillRadial(
                context: &context,
                center: center,
                radius: segmentRadius,
                stops: [
                    (0.00, palette.color(hue: hue + Double(progress) * 52, alpha: 0.26 * flow * palette.alphaScale)),
                    (0.52, palette.color(hue: hue + 26 + Double(progress) * 68, alpha: 0.14 * flow * palette.alphaScale)),
                    (1.00, palette.color(hue: hue + 72, alpha: 0)),
                ]
            )
        }
    }

    private func drawPhaseWash(context: inout GraphicsContext, size: CGSize, phaseElapsed: TimeInterval) {
        let wash = phase.washStrength * (1 - exp(-phaseElapsed * 0.62))
        guard wash > 0.01 else { return }
        var washContext = context
        washContext.blendMode = palette.blendMode
        fillRadial(
            context: &washContext,
            center: CGPoint(x: size.width * 0.52, y: size.height * phase.washCenterY),
            radius: min(size.width, size.height) * 0.58,
            stops: [
                (0.00, palette.pulsePrimary.opacity(0.10 * wash * palette.alphaScale)),
                (0.68, palette.pulseSecondary.opacity(0.055 * wash * palette.alphaScale)),
                (1.00, palette.pulseSecondary.opacity(0)),
            ]
        )
    }

    private func drawParticles(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        var particleContext = context
        particleContext.blendMode = palette.blendMode
        let count = Int(24 + defaultParticleAmount * 90)

        for index in 0..<count {
            let seed = Double(index) * 12.9898
            let speed = 0.10 + seeded(seed + 1) * 0.22
            let progress = (time * speed + seeded(seed + 2)).truncatingRemainder(dividingBy: 1)
            let life = sin(progress * .pi)
            let x = (seeded(seed + 3) + sin(time * 2 + seed) * 0.018) * size.width
            let y = size.height * (0.92 - progress * 0.84)
            let radius = max(1, min(size.width, size.height) * (0.004 + seeded(seed + 4) * 0.007))
            let hue = palette.blobHues[index % min(4, palette.blobHues.count)]
            fillRadial(
                context: &particleContext,
                center: CGPoint(x: x, y: y),
                radius: radius * 5,
                stops: [
                    (0.00, palette.color(hue: hue, alpha: 0.42 * life * palette.particleAlpha)),
                    (0.55, palette.color(hue: hue + 24, alpha: 0.12 * life * palette.particleAlpha)),
                    (1.00, palette.color(hue: hue + 70, alpha: 0)),
                ]
            )
        }
    }

    private func fillRadial(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        stops: [(Double, Color)]
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let path = Path(ellipseIn: rect)
        let gradientStops = stops.map { Gradient.Stop(color: $0.1, location: $0.0) }
        context.fill(
            path,
            with: .radialGradient(
                Gradient(stops: gradientStops),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func wave(seed: Double, time: TimeInterval, amplitude: CGFloat) -> CGFloat {
        CGFloat(sin(time + seed) + sin(time * 0.43 + seed * 2.1) * 0.55) * amplitude
    }

    private func seeded(_ value: Double) -> Double {
        let raw = sin(value) * 43_758.5453
        return raw - floor(raw)
    }
}
