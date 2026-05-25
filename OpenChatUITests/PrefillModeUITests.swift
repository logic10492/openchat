import XCTest

final class PrefillModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_prefillMode_alternatesUserAndCharacterMessages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-chat-prefill"]
        app.launch()

        let inputModeMenu = app.buttons["chat.inputModeMenu"]
        XCTAssertTrue(inputModeMenu.waitForExistence(timeout: 5))
        inputModeMenu.tap()
        tapMenuItem(
            identifiers: ["chat.inputMode.prefill", "Prefill dialogue", "预填充对话"],
            app: app
        )

        XCTAssertTrue(app.staticTexts["chat.prefillModeHint"].waitForExistence(timeout: 5))
        let input = chatInput(app: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Mara writes the opening reply herself.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["Mara writes the opening reply herself."].waitForExistence(timeout: 5))
        XCTAssertTrue(prefillMessage(app: app, role: "assistant", content: "Mara writes the opening reply herself.").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.prefillModeHint"].waitForExistence(timeout: 2))

        input.tap()
        input.typeText("I answer inside the prefill loop.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["I answer inside the prefill loop."].waitForExistence(timeout: 5))
        XCTAssertTrue(prefillMessage(app: app, role: "user", content: "I answer inside the prefill loop.").waitForExistence(timeout: 5))

        input.tap()
        input.typeText("Mara writes again after the user side.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["Mara writes again after the user side."].waitForExistence(timeout: 5))
        XCTAssertTrue(prefillMessage(app: app, role: "assistant", content: "Mara writes again after the user side.").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["UI stage reply"].waitForExistence(timeout: 1))
    }

    @MainActor
    private func prefillMessage(app: XCUIApplication, role: String, content: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "chat.message.\(role).", content))
            .firstMatch
    }

    @MainActor
    private func tapMenuItem(identifiers: [String], app: XCUIApplication) {
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier]
            if element.waitForExistence(timeout: 2) {
                element.tap()
                return
            }
        }
        attachHierarchy(app: app, name: "missing-prefill-menu-item")
        XCTFail("Missing prefill menu item")
    }

    @MainActor
    private func chatInput(app: XCUIApplication) -> XCUIElement {
        let textField = app.textFields["chat.inputText"]
        if textField.waitForExistence(timeout: 1) {
            return textField
        }
        let textView = app.textViews["chat.inputText"]
        if textView.waitForExistence(timeout: 1) {
            return textView
        }
        return app.descendants(matching: .any)["chat.inputText"]
    }

    @MainActor
    private func attachHierarchy(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
