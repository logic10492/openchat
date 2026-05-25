import XCTest
import UIKit

final class MessageBubbleContextMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_userBubbleContextMenuPreviewKeepsBubbleBackground() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-chat-context-menu",
        ]
        app.launch()

        openSeedConversationIfNeeded(app: app)

        let bubble = userFixtureMessage(app: app)
        if !bubble.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-context-menu-fixture-message")
            XCTFail("Missing context menu fixture message")
            return
        }
        let bubbleFrame = bubble.frame
        let pressPoint = CGPoint(x: bubbleFrame.maxX - 20, y: bubbleFrame.midY)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: pressPoint.x, dy: pressPoint.y))
            .press(forDuration: 1.5)

        XCTAssertTrue(copyMenuButton(app: app).waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "message-bubble-context-menu-preview"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            screenshotContainsOutgoingBubbleBackground(
                app.screenshot(),
                near: bubbleFrame,
                screenFrame: app.frame
            ),
            "Long-press context menu preview lost the outgoing bubble background."
        )
    }

    @MainActor
    private func openSeedConversationIfNeeded(app: XCUIApplication) {
        let messageText = app.staticTexts["Context menu bubble background fixture"]
        if messageText.waitForExistence(timeout: 2) {
            return
        }

        let conversation = app.descendants(matching: .any)["sidebar.conversation.ui-test-conversation"]
        if conversation.waitForExistence(timeout: 5) {
            conversation.tap()
        }
    }

    @MainActor
    private func copyMenuButton(app: XCUIApplication) -> XCUIElement {
        let copyButton = app.buttons["Copy"]
        if copyButton.exists {
            return copyButton
        }
        return app.buttons["复制"]
    }

    @MainActor
    private func userFixtureMessage(app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(identifier: "chat.message.user.ui-context-menu-user")
            .matching(NSPredicate(format: "label == %@", "Context menu bubble background fixture"))
            .firstMatch
    }

    @MainActor
    private func screenshotContainsOutgoingBubbleBackground(
        _ screenshot: XCUIScreenshot,
        near frame: CGRect,
        screenFrame: CGRect
    ) -> Bool {
        guard let image = UIImage(data: screenshot.pngRepresentation),
              let cgImage = image.cgImage
        else {
            return false
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard pixelWidth > 0, pixelHeight > 0, screenFrame.width > 0, screenFrame.height > 0 else {
            return false
        }

        let scaleX = CGFloat(pixelWidth) / screenFrame.width
        let scaleY = CGFloat(pixelHeight) / screenFrame.height
        let searchFrame = frame.insetBy(dx: -24, dy: -24)
        let minX = max(0, Int(searchFrame.minX * scaleX))
        let maxX = min(pixelWidth - 1, Int(searchFrame.maxX * scaleX))
        let minY = max(0, Int(searchFrame.minY * scaleY))
        let maxY = min(pixelHeight - 1, Int(searchFrame.maxY * scaleY))
        guard minX < maxX, minY < maxY else {
            return false
        }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * pixelWidth
        var data = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)
        return data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

            for y in minY...maxY {
                for x in minX...maxX {
                    let index = y * bytesPerRow + x * bytesPerPixel
                    let red = rawBuffer[index]
                    let green = rawBuffer[index + 1]
                    let blue = rawBuffer[index + 2]
                    if blue > 170 && green > 80 && green < 180 && red < 80 {
                        return true
                    }
                }
            }
            return false
        }
    }

    @MainActor
    private func attachHierarchy(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
