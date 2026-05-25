import Testing
import UIKit

@testable import OpenChat

@Suite("Vibe background driver")
struct VibeBackgroundDriverTests {
    @Test func test_phaseChangeKeepsContinuousMotionState() {
        var driver = VibeBackgroundDriver()
        let palette = VibeBackgroundUIKitPalette(userInterfaceStyle: .dark, reduceTransparency: false)
        let size = CGSize(width: 160, height: 240)

        driver.setPhase(.waiting, reduceMotion: false)
        driver.update(deltaTime: 0.5, size: size, palette: palette, reduceMotion: false)
        let waitingFlow = driver.flow
        let waitingBandT = driver.bandT

        driver.setPhase(.streaming, reduceMotion: false)

        #expect(driver.flow == waitingFlow)
        #expect(driver.bandT == waitingBandT)

        driver.update(deltaTime: 0.5, size: size, palette: palette, reduceMotion: false)

        #expect(driver.flow > waitingFlow)
        #expect(driver.bandT > waitingBandT)
    }

    @Test func test_reduceMotionStopsParticleState() {
        var driver = VibeBackgroundDriver()
        let palette = VibeBackgroundUIKitPalette(userInterfaceStyle: .dark, reduceTransparency: false)
        let size = CGSize(width: 160, height: 240)

        driver.setPhase(.streaming, reduceMotion: false)
        driver.update(deltaTime: 0.5, size: size, palette: palette, reduceMotion: false)

        #expect(!driver.particles.isEmpty)

        driver.setPhase(.streaming, reduceMotion: true)

        #expect(driver.particles.isEmpty)
        #expect(driver.flow > 0)
    }
}
