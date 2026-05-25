import UIKit

struct VibeBackgroundUIKitPalette {
    let baseColors: [UIColor]
    let bandHues: [Double]
    let blobHues: [Double]
    let alphaScale: Double
    let particleAlpha: Double
    let bandBaseSpeed: Double
    let bandFlowSpeed: Double
    let bandImpulseSpeed: Double
    let blendMode: CGBlendMode
    let pulsePrimary: UIColor
    let pulseSecondary: UIColor
    let bottomRadialColor: UIColor
    let shadeColors: [UIColor]
    let shadeLocations: [CGFloat]
    let saturation: CGFloat
    let brightness: CGFloat

    init(userInterfaceStyle: UIUserInterfaceStyle, reduceTransparency: Bool) {
        if userInterfaceStyle == .dark {
            baseColors = [
                UIColor(red: 0.03, green: 0.06, blue: 0.09, alpha: 1),
                UIColor(red: 0.07, green: 0.03, blue: 0.09, alpha: 1),
                UIColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 1),
                UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
            ]
            bandHues = [176, 42, 304, 116, 204, 326, 28]
            blobHues = [24, 316, 42, 176, 288, 198, 112]
            alphaScale = 1
            particleAlpha = 1
            bandBaseSpeed = 0.22
            bandFlowSpeed = 0.16
            bandImpulseSpeed = 1.25
            blendMode = .screen
            pulsePrimary = UIColor(red: 1.00, green: 0.60, blue: 0.34, alpha: 1)
            pulseSecondary = UIColor(red: 1.00, green: 0.37, blue: 0.55, alpha: 1)
            bottomRadialColor = UIColor(red: 1.00, green: 0.51, blue: 0.22, alpha: 0.18)
            shadeColors = [
                UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 0.18),
                UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: reduceTransparency ? 0.82 : 0.62),
                UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: reduceTransparency ? 0.90 : 0.82),
            ]
            shadeLocations = [0, 0.72, 1]
            saturation = 1.25
            brightness = -0.02
        } else {
            baseColors = [
                UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1),
                UIColor(red: 0.92, green: 0.95, blue: 0.94, alpha: 1),
                UIColor(red: 0.96, green: 0.85, blue: 0.70, alpha: 1),
                UIColor(red: 1.00, green: 0.97, blue: 0.91, alpha: 1),
            ]
            bandHues = [188, 34, 286, 132, 212, 316, 48]
            blobHues = [34, 324, 52, 184, 286, 202, 122]
            alphaScale = 0.62
            particleAlpha = 0.72
            bandBaseSpeed = 0.34
            bandFlowSpeed = 0.28
            bandImpulseSpeed = 2.4
            blendMode = .multiply
            pulsePrimary = UIColor(red: 1.00, green: 0.67, blue: 0.28, alpha: 1)
            pulseSecondary = UIColor(red: 0.96, green: 0.41, blue: 0.56, alpha: 1)
            bottomRadialColor = UIColor(red: 1.00, green: 0.73, blue: 0.37, alpha: 0.20)
            shadeColors = [
                UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 0.06),
                UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: reduceTransparency ? 0.54 : 0.28),
                UIColor(red: 0.98, green: 0.93, blue: 0.86, alpha: reduceTransparency ? 0.66 : 0.46),
            ]
            shadeLocations = [0, 0.58, 1]
            saturation = 1.08
            brightness = 0.06
        }
    }

    func color(hue: Double, alpha: Double) -> UIColor {
        UIColor(
            hue: CGFloat(normalizedHue(hue)),
            saturation: 0.92,
            brightness: 0.62,
            alpha: CGFloat(max(0, min(1, alpha)))
        )
    }

    private func normalizedHue(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 360)
        return (value < 0 ? value + 360 : value) / 360
    }
}
