import SwiftUI

struct VibeBackgroundPalette {
    let baseColors: [Color]
    let bandHues: [Double]
    let blobHues: [Double]
    let alphaScale: Double
    let particleAlpha: Double
    let bandBaseSpeed: Double
    let bandFlowSpeed: Double
    let bandImpulseSpeed: Double
    let blendMode: GraphicsContext.BlendMode
    let pulsePrimary: Color
    let pulseSecondary: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            baseColors = [
                Color(red: 0.03, green: 0.06, blue: 0.09),
                Color(red: 0.07, green: 0.03, blue: 0.09),
                Color(red: 0.08, green: 0.06, blue: 0.04),
                Color(red: 0.02, green: 0.02, blue: 0.02),
            ]
            bandHues = [176, 42, 304, 116, 204, 326, 28]
            blobHues = [24, 316, 42, 176, 288, 198, 112]
            alphaScale = 1
            particleAlpha = 1
            bandBaseSpeed = 0.22
            bandFlowSpeed = 0.16
            bandImpulseSpeed = 1.25
            blendMode = .screen
            pulsePrimary = Color(red: 1.00, green: 0.60, blue: 0.34)
            pulseSecondary = Color(red: 1.00, green: 0.37, blue: 0.55)
        } else {
            baseColors = [
                Color(red: 0.97, green: 0.94, blue: 0.87),
                Color(red: 0.92, green: 0.95, blue: 0.94),
                Color(red: 0.96, green: 0.85, blue: 0.70),
                Color(red: 1.00, green: 0.97, blue: 0.91),
            ]
            bandHues = [188, 34, 286, 132, 212, 316, 48]
            blobHues = [34, 324, 52, 184, 286, 202, 122]
            alphaScale = 0.62
            particleAlpha = 0.72
            bandBaseSpeed = 0.34
            bandFlowSpeed = 0.28
            bandImpulseSpeed = 2.4
            blendMode = .multiply
            pulsePrimary = Color(red: 1.00, green: 0.67, blue: 0.28)
            pulseSecondary = Color(red: 0.96, green: 0.41, blue: 0.56)
        }
    }

    func color(hue: Double, alpha: Double) -> Color {
        Color(
            hue: normalizedHue(hue),
            saturation: 0.92,
            brightness: 0.62
        )
        .opacity(max(0, min(1, alpha)))
    }

    private func normalizedHue(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 360)
        return (value < 0 ? value + 360 : value) / 360
    }
}
