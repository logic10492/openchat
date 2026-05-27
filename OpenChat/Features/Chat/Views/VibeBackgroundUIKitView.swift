import CoreImage.CIFilterBuiltins
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class VibeBackgroundUIKitView: UIView {
    private let renderScale: CGFloat = 0.28
    private let horizontalOverscan: CGFloat = 1.14
    private let verticalOverscan: CGFloat = 1.14
    private let blurRadius: CGFloat = 18

    private var driver = VibeBackgroundDriver()
    private let displayLinkBox = VibeBackgroundDisplayLinkBox()
    private var lastRenderedTargetTimestamp: CFTimeInterval?
    private var appliedFrameRatePolicy: VibeBackgroundFrameRatePolicy?
    private var sequenceTask: Task<Void, Never>?
    private var isGenerating = false
    private var isTimelineScrolling = false
    private var reduceMotion = false
    private var reduceTransparency = false
    private var colorScheme: ColorScheme = .dark
    private var currentRenderSize: CGSize = .zero
    private var cachedBaseImage: UIImage?
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

    override init(frame: CGRect) {
        super.init(frame: frame)
        initializeView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initializeView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            sequenceTask?.cancel()
            stopDisplayLink()
        } else {
            startDisplayLinkIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let nextRenderSize = renderSize(for: bounds.size)
        if nextRenderSize != currentRenderSize {
            currentRenderSize = nextRenderSize
            cachedBaseImage = nil
            setNeedsDisplay()
        }
    }

    func configure(
        isGenerating: Bool,
        isTimelineScrolling: Bool,
        colorScheme: ColorScheme,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) {
        let didChangeAccessibility = self.reduceMotion != reduceMotion
            || self.reduceTransparency != reduceTransparency
        let didChangeTheme = self.colorScheme != colorScheme

        self.colorScheme = colorScheme
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency

        if self.isTimelineScrolling != isTimelineScrolling {
            self.isTimelineScrolling = isTimelineScrolling
            if isTimelineScrolling {
                stopDisplayLink()
            } else {
                startDisplayLinkIfNeeded()
            }
        }

        if didChangeTheme || didChangeAccessibility {
            cachedBaseImage = nil
            driver.setPhase(driver.phase, reduceMotion: reduceMotion)
        }

        if self.isGenerating != isGenerating || didChangeAccessibility {
            self.isGenerating = isGenerating
            if isGenerating {
                startGeneratingSequence()
            } else {
                finishGeneratingSequence()
            }
        }

        if reduceMotion {
            stopDisplayLink()
            setNeedsDisplay()
        } else {
            startDisplayLinkIfNeeded()
        }
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let renderSize = currentRenderSize == .zero ? renderSize(for: bounds.size) : currentRenderSize
        guard let image = makeFrameImage(size: renderSize) else { return }

        context.saveGState()
        context.interpolationQuality = .high
        image.draw(in: bounds.insetBy(
            dx: -bounds.width * (horizontalOverscan - 1) / 2,
            dy: -bounds.height * (verticalOverscan - 1) / 2
        ))
        context.restoreGState()
    }

    private func initializeView() {
        isOpaque = true
        backgroundColor = .systemGroupedBackground
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    private func startGeneratingSequence() {
        sequenceTask?.cancel()
        setPhase(.waiting)
        guard !reduceMotion else { return }

        sequenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.setPhase(.streaming)
            }
        }
    }

    private func finishGeneratingSequence() {
        sequenceTask?.cancel()
        guard driver.phase != .idle else { return }
        setPhase(.completing)
        guard !reduceMotion else {
            setPhase(.idle)
            return
        }

        sequenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_900))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.setPhase(.idle)
            }
        }
    }

    private func setPhase(_ phase: VibeBackgroundPhase) {
        driver.setPhase(phase, reduceMotion: reduceMotion)
        appliedFrameRatePolicy = nil
        if let displayLink = displayLinkBox.displayLink {
            updateFrameRatePolicy(for: displayLink)
        }
        setNeedsDisplay()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLinkBox.displayLink == nil, !reduceMotion, !isTimelineScrolling else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick(_:)))
        updateFrameRatePolicy(for: link)
        link.add(to: .main, forMode: .common)
        displayLinkBox.displayLink = link
    }

    private func stopDisplayLink() {
        displayLinkBox.displayLink?.invalidate()
        displayLinkBox.displayLink = nil
        lastRenderedTargetTimestamp = nil
        appliedFrameRatePolicy = nil
    }

    @objc
    private func displayLinkDidTick(_ link: CADisplayLink) {
        updateFrameRatePolicy(for: link)
        guard shouldDrawFrame(for: link) else { return }

        let targetTimestamp = link.targetTimestamp
        let deltaTime = frameDeltaTime(for: link, targetTimestamp: targetTimestamp)
        lastRenderedTargetTimestamp = targetTimestamp
        driver.update(
            deltaTime: deltaTime,
            size: currentRenderSize == .zero ? renderSize(for: bounds.size) : currentRenderSize,
            palette: palette(),
            reduceMotion: reduceMotion
        )
        setNeedsDisplay()
    }

    private func updateFrameRatePolicy(for link: CADisplayLink) {
        let policy = driver.phase.frameRatePolicy(maximumFramesPerSecond: maximumFramesPerSecond)
        guard appliedFrameRatePolicy != policy else { return }
        link.preferredFrameRateRange = policy.range
        appliedFrameRatePolicy = policy
    }

    private var maximumFramesPerSecond: Float {
        let screenMaximum = window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        return Float(max(60, screenMaximum))
    }

    private func frameDeltaTime(for link: CADisplayLink, targetTimestamp: CFTimeInterval) -> TimeInterval {
        if let lastRenderedTargetTimestamp {
            return targetTimestamp - lastRenderedTargetTimestamp
        }
        return max(0.001, targetTimestamp - link.timestamp)
    }

    private func renderSize(for visibleSize: CGSize) -> CGSize {
        CGSize(
            width: max(168, ceil(visibleSize.width * renderScale)),
            height: max(196, ceil(visibleSize.height * renderScale))
        )
    }

    private func shouldDrawFrame(for link: CADisplayLink) -> Bool {
        guard let lastRenderedTargetTimestamp else { return true }

        let policy = appliedFrameRatePolicy
            ?? driver.phase.frameRatePolicy(maximumFramesPerSecond: maximumFramesPerSecond)
        let displayInterval = max(0.001, link.targetTimestamp - link.timestamp)
        let elapsed = link.targetTimestamp - lastRenderedTargetTimestamp
        let timingTolerance = min(displayInterval * 0.1, 0.001)
        return elapsed + timingTolerance >= policy.minimumRenderInterval
    }

    private func palette() -> VibeBackgroundUIKitPalette {
        VibeBackgroundUIKitPalette(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light,
            reduceTransparency: reduceTransparency
        )
    }

    private func makeFrameImage(size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let palette = palette()

        let rawImage = renderer.image { context in
            let cgContext = context.cgContext
            drawBase(in: cgContext, size: size, palette: palette)
            drawBands(in: cgContext, size: size, palette: palette)
            drawBlobs(in: cgContext, size: size, palette: palette)
            drawPulse(in: cgContext, size: size, palette: palette)
            drawParticles(in: cgContext, size: size, palette: palette)
            drawShade(in: cgContext, size: size, palette: palette)
        }

        guard !reduceTransparency else { return rawImage }
        return rawImage.applyingVibePostprocessing(
            blurRadius: blurRadius,
            saturation: palette.saturation,
            brightness: palette.brightness,
            context: ciContext
        )
    }

    private func drawBase(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        if let cachedBaseImage, cachedBaseImage.size == size {
            cachedBaseImage.draw(at: .zero)
            return
        }

        let image = makeBaseImage(size: size, palette: palette)
        cachedBaseImage = image
        image.draw(at: .zero)
    }

    private func makeBaseImage(size: CGSize, palette: VibeBackgroundUIKitPalette) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: palette.baseColors.map(\.cgColor) as CFArray,
                locations: [0, 0.42, 0.68, 1]
            )
            cgContext.drawLinearGradient(
                gradient!,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private func drawBands(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        context.saveGState()
        context.setBlendMode(palette.blendMode)

        for index in 0..<palette.bandHues.count {
            let yBase = size.height * (0.12 + CGFloat(index) * 0.095 + CGFloat(driver.flow) * 0.06)
            let lateral = sin(driver.bandT * (0.92 + Double(index) * 0.07) + Double(index) * 1.7)
                * size.width
                * (0.08 + CGFloat(driver.flow) * 0.22)
            let diagonal = (CGFloat(index) - 3) * size.width * 0.018 * CGFloat(driver.flow)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -size.width * 0.24 + lateral, y: yBase))

            for step in 0...10 {
                let progress = CGFloat(step) / 10
                let x = progress * size.width * 1.48 - size.width * 0.22 + lateral + diagonal * progress
                let y = yBase + wave(
                    seed: Double(index) * 1.7 + Double(step),
                    time: driver.bandT * (0.34 + driver.flow * 0.28),
                    amplitude: size.height * (0.04 + CGFloat(driver.flow) * 0.06)
                )
                path.addLine(to: CGPoint(x: x, y: y))
            }

            context.setStrokeColor(
                palette.color(
                    hue: palette.bandHues[index] + driver.flow * 46,
                    alpha: (0.075 + driver.flow * 0.16) * palette.alphaScale
                ).cgColor
            )
            context.setLineWidth(size.height * (0.07 + CGFloat(driver.flow) * 0.052))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path.cgPath)
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawBlobs(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        context.saveGState()
        context.setBlendMode(palette.blendMode)

        for blob in VibeBackgroundBlob.all {
            let hue = palette.blobHues[blob.hueIndex]
            let driftX = wave(seed: blob.seed, time: driver.bandT * blob.speed, amplitude: 0.035)
            let driftY = wave(seed: blob.seed + 4.5, time: driver.bandT * blob.speed * 0.8, amplitude: 0.03)
            let x = (blob.x + driftX + CGFloat(driver.flow) * wave(seed: blob.seed + 9, time: driver.bandT * 0.25, amplitude: 0.05)) * size.width
            let y = (blob.y + driftY - CGFloat(driver.flow) * blob.y * 0.18) * size.height
            let radius = blob.radius * min(size.width, size.height) * (1 + wave(seed: blob.seed + 8, time: driver.bandT * 0.62, amplitude: 0.12))
            let origin = CGPoint(x: x, y: y)

            if driver.flow > 0.28 {
                drawStreamTail(in: context, origin: origin, radius: radius, seed: blob.seed, hue: hue, palette: palette)
            }

            fillRadial(
                in: context,
                center: origin,
                startRadius: 0,
                endRadius: radius * (1.2 + CGFloat(driver.flow) * 0.45),
                stops: [
                    (0.00, palette.color(hue: hue, alpha: (0.44 - driver.flow * 0.12) * palette.alphaScale)),
                    (0.48, palette.color(hue: hue + 28, alpha: 0.24 * palette.alphaScale)),
                    (1.00, palette.color(hue: hue + 74, alpha: 0)),
                ]
            )
        }

        context.restoreGState()
    }

    private func drawStreamTail(
        in context: CGContext,
        origin: CGPoint,
        radius: CGFloat,
        seed: Double,
        hue: Double,
        palette: VibeBackgroundUIKitPalette
    ) {
        let streamLength = radius * (2.4 + CGFloat(driver.flow) * 4.0)
        for index in 0..<5 {
            let progress = CGFloat(index) / 4
            let sway = sin(driver.bandT * 0.92 + seed * 3 + Double(progress) * 4) * radius * 0.45 * CGFloat(driver.flow)
            let center = CGPoint(
                x: origin.x + sway + (progress - 0.5) * radius * 0.35,
                y: origin.y - progress * streamLength
            )
            let segmentRadius = radius * (0.72 + (0.28 - 0.72) * progress) * (1 - 0.25 * CGFloat(driver.flow))
            fillRadial(
                in: context,
                center: center,
                startRadius: 0,
                endRadius: segmentRadius,
                stops: [
                    (0.00, palette.color(hue: hue + Double(progress) * 52, alpha: 0.26 * driver.flow * palette.alphaScale)),
                    (0.52, palette.color(hue: hue + 26 + Double(progress) * 68, alpha: 0.14 * driver.flow * palette.alphaScale)),
                    (1.00, palette.color(hue: hue + 72, alpha: 0)),
                ]
            )
        }
    }

    private func drawPulse(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        let phaseWash = driver.phase.washStrength * driver.pulse
        let wash = max(driver.pulse, phaseWash)
        guard wash > 0.01 else { return }

        context.saveGState()
        context.setBlendMode(palette.blendMode)
        fillRadial(
            in: context,
            center: CGPoint(x: size.width * 0.52, y: size.height * driver.phase.washCenterY),
            startRadius: min(size.width, size.height) * 0.08,
            endRadius: min(size.width, size.height) * (0.24 + CGFloat(1 - min(1, wash)) * 0.12),
            stops: [
                (0.00, palette.pulsePrimary.withAlphaComponent(CGFloat(0.05 * wash * palette.alphaScale))),
                (0.72, palette.pulseSecondary.withAlphaComponent(CGFloat(0.035 * wash * palette.alphaScale))),
                (1.00, palette.pulseSecondary.withAlphaComponent(0)),
            ]
        )
        context.restoreGState()
    }

    private func drawParticles(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        guard !driver.particles.isEmpty else { return }
        context.saveGState()
        context.setBlendMode(palette.blendMode)

        for particle in driver.particles {
            let life = max(0, 1 - particle.age / particle.lifetime)
            fillRadial(
                in: context,
                center: CGPoint(x: particle.x, y: particle.y),
                startRadius: 0,
                endRadius: particle.radius * 5,
                stops: [
                    (0.00, palette.color(hue: particle.hue, alpha: 0.42 * life * palette.particleAlpha)),
                    (0.55, palette.color(hue: particle.hue + 24, alpha: 0.12 * life * palette.particleAlpha)),
                    (1.00, palette.color(hue: particle.hue + 70, alpha: 0)),
                ]
            )
        }

        context.restoreGState()
    }

    private func drawShade(in context: CGContext, size: CGSize, palette: VibeBackgroundUIKitPalette) {
        context.saveGState()

        fillRadial(
            in: context,
            center: CGPoint(
                x: size.width * (colorScheme == .dark ? 0.50 : 0.47),
                y: size.height * 0.88
            ),
            startRadius: 0,
            endRadius: min(size.width, size.height) * 0.76,
            stops: [
                (0.00, palette.bottomRadialColor),
                (1.00, palette.bottomRadialColor.withAlphaComponent(0)),
            ]
        )

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: palette.shadeColors.map(\.cgColor) as CFArray,
            locations: palette.shadeLocations
        )
        context.drawLinearGradient(
            gradient!,
            start: .zero,
            end: CGPoint(x: 0, y: size.height),
            options: []
        )

        context.restoreGState()
    }

    private func fillRadial(
        in context: CGContext,
        center: CGPoint,
        startRadius: CGFloat,
        endRadius: CGFloat,
        stops: [(CGFloat, UIColor)]
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: stops.map { $0.1.cgColor } as CFArray,
            locations: stops.map(\.0)
        ) else { return }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: startRadius,
            endCenter: center,
            endRadius: endRadius,
            options: [.drawsAfterEndLocation]
        )
    }

    private func wave(seed: Double, time: TimeInterval, amplitude: CGFloat) -> CGFloat {
        CGFloat(sin(time + seed) + sin(time * 0.43 + seed * 2.1) * 0.55) * amplitude
    }
}

private final class VibeBackgroundDisplayLinkBox {
    var displayLink: CADisplayLink?

    deinit {
        displayLink?.invalidate()
    }
}

private struct VibeBackgroundFrameRatePolicy: Equatable {
    let minimum: Float
    let maximum: Float
    let preferred: Float
    let maximumDrawsPerSecond: Float

    var range: CAFrameRateRange {
        CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: preferred)
    }

    var minimumRenderInterval: TimeInterval {
        TimeInterval(1 / maximumDrawsPerSecond)
    }
}

private extension VibeBackgroundPhase {
    func frameRatePolicy(maximumFramesPerSecond screenMaximum: Float) -> VibeBackgroundFrameRatePolicy {
        let screenMaximum = max(60, screenMaximum)

        switch self {
        case .idle, .completing:
            return VibeBackgroundFrameRatePolicy(
                minimum: 10,
                maximum: min(24, screenMaximum),
                preferred: min(24, screenMaximum),
                maximumDrawsPerSecond: 24
            )
        case .waiting:
            return VibeBackgroundFrameRatePolicy(
                minimum: 15,
                maximum: min(30, screenMaximum),
                preferred: min(30, screenMaximum),
                maximumDrawsPerSecond: 30
            )
        case .streaming:
            return VibeBackgroundFrameRatePolicy(
                minimum: 24,
                maximum: min(60, screenMaximum),
                preferred: min(60, screenMaximum),
                maximumDrawsPerSecond: 60
            )
        }
    }
}

private extension UIImage {
    func applyingVibePostprocessing(
        blurRadius: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        context: CIContext
    ) -> UIImage? {
        guard let inputImage = CIImage(image: self) else { return nil }
        var outputImage = inputImage

        if blurRadius > 0 {
            let blurFilter = CIFilter.gaussianBlur()
            blurFilter.inputImage = inputImage.clampedToExtent()
            blurFilter.radius = Float(blurRadius)
            if let blurred = blurFilter.outputImage?.cropped(to: inputImage.extent) {
                outputImage = blurred
            }
        }

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = outputImage
        colorFilter.saturation = Float(saturation)
        colorFilter.brightness = Float(brightness)
        if let adjusted = colorFilter.outputImage {
            outputImage = adjusted
        }

        return UIImage.render(ciImage: outputImage, size: size, context: context)
    }

    private static func render(ciImage: CIImage, size: CGSize, context: CIContext) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up).resized(to: size)
    }

    private func resized(to size: CGSize) -> UIImage? {
        guard self.size != size else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
