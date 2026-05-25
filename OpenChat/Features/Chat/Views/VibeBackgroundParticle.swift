import Foundation
import CoreGraphics

struct VibeBackgroundParticle {
    var x: CGFloat
    var y: CGFloat
    var velocityX: CGFloat
    var velocityY: CGFloat
    var age: TimeInterval
    let lifetime: TimeInterval
    let hue: Double
    let radius: CGFloat
}
