import XCTest
import UIKit

final class IPadChatTimelineLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningConversationFromSidebarKeepsBubblesInsideTimeline() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad split-view timeline layout regression coverage.")
        }

        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-chat-context-menu",
            "--ui-testing-start-unselected",
        ]
        app.launch()

        var conversation = sidebarConversation(app: app)
        if !conversation.waitForExistence(timeout: 2) {
            revealSidebar(app: app)
            conversation = sidebarConversation(app: app)
        }
        if !conversation.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-sidebar-conversation")
            XCTFail("Missing seeded conversation in sidebar")
            return
        }
        conversation.tap()

        let timeline = app.collectionViews["chat.timeline.collectionView"]
        if !timeline.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-chat-timeline")
            XCTFail("Missing chat timeline after opening seeded conversation")
            return
        }

        let userMessage = app.staticTexts["chat.message.user.ui-context-menu-user"]
        let assistantMessage = app.staticTexts["chat.message.assistant.ui-context-menu-assistant"]
        if !userMessage.waitForExistence(timeout: 5) || !assistantMessage.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-chat-fixture-messages")
            XCTFail("Missing seeded chat messages")
            return
        }

        assertElement(userMessage, isContainedIn: timeline, name: "user message")
        assertElement(assistantMessage, isContainedIn: timeline, name: "assistant message")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ipad-sidebar-chat-timeline-layout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertElement(
        _ element: XCUIElement,
        isContainedIn container: XCUIElement,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        let containerFrame = container.frame
        let tolerance: CGFloat = 2
        XCTAssertGreaterThanOrEqual(
            frame.minX,
            containerFrame.minX - tolerance,
            "\(name) starts outside timeline: element=\(frame), timeline=\(containerFrame)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxX,
            containerFrame.maxX + tolerance,
            "\(name) ends outside timeline: element=\(frame), timeline=\(containerFrame)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func sidebarConversation(app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(identifier: "sidebar.conversation.ui-test-conversation")
            .matching(NSPredicate(format: "label == %@", "UI Stage Test"))
            .firstMatch
    }

    @MainActor
    private func revealSidebar(app: XCUIApplication) {
        for label in ["Show Sidebar", "Sidebar", "显示边栏", "显示侧边栏", "边栏"] {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
        }

        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 32, dy: 56))
            .tap()
    }

    @MainActor
    private func attachHierarchy(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
