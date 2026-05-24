import XCTest

final class StageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_stageControlsAndDirectorInputIsolation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let settings = app.buttons["chat.settingsButton"]
        if !settings.waitForExistence(timeout: 5) {
            let conversation = app.descendants(matching: .any)["sidebar.conversation.ui-test-conversation"]
            XCTAssertTrue(conversation.waitForExistence(timeout: 5))
            conversation.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let form = app.collectionViews["chatSettings.form"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let directorMode = app.descendants(matching: .any)["stage.directorModePicker"]

        if !directorMode.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-director-mode")
            XCTFail("Missing Director Mode picker")
            return
        }
        XCTAssertFalse(app.descendants(matching: .any)["chat.characterPicker"].exists)
        directorMode.tap()
        tapOption("Agent", app: app)

        let addParticipant = app.descendants(matching: .any)["stage.addParticipantPicker"]
        if !addParticipant.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-add-participant")
            XCTFail("Missing Add Participant picker")
            return
        }

        XCTAssertTrue(app.staticTexts["Io"].waitForExistence(timeout: 5))

        app.buttons["chatSettings.doneButton"].tap()

        let directorTools = app.buttons["chat.directorToolsButton"]
        XCTAssertTrue(directorTools.waitForExistence(timeout: 5))
        directorTools.tap()

        let directorPanel = app.descendants(matching: .any)["chat.directorToolsPanel"]
        XCTAssertTrue(directorPanel.waitForExistence(timeout: 5))
        let inputMode = app.descendants(matching: .any)["chat.stageInputModePicker"]
        XCTAssertTrue(inputMode.waitForExistence(timeout: 5))
        tapStageInputMode(.director, app: app)
        XCTAssertTrue(app.descendants(matching: .any)["chat.directorInstructionHint"].waitForExistence(timeout: 5))
        let input = chatInput(app: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Keep Io quiet until Mara speaks.")
        app.buttons["chat.sendButton"].tap()
        XCTAssertFalse(app.staticTexts["Keep Io quiet until Mara speaks."].waitForExistence(timeout: 1))

        tapStageInputMode(.participant, app: app)
        let maraResponder = app.descendants(matching: .any)["chat.directorResponder.Mara"]
        XCTAssertTrue(maraResponder.waitForExistence(timeout: 5))
        let ioResponder = app.descendants(matching: .any)["chat.directorResponder.Io"]
        XCTAssertTrue(ioResponder.waitForExistence(timeout: 5))

        let collapse = app.buttons["chat.directorToolsCollapse"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()
        XCTAssertFalse(directorPanel.waitForExistence(timeout: 1))

        input.tap()
        input.typeText("Mara, answer first.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["Mara, answer first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mara UI stage reply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Io UI stage reply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Io"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "telegram-style-stage-chat"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func tapOption(_ title: String, app: XCUIApplication) {
        let button = app.buttons[title]
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
        let staticText = app.staticTexts[title]
        if staticText.waitForExistence(timeout: 2) {
            staticText.tap()
            return
        }
        attachHierarchy(app: app, name: "missing-option-\(title)")
        XCTFail("Missing option \(title)")
    }

    @MainActor
    private func tapStageInputMode(_ mode: StageInputMode, app: XCUIApplication) {
        for identifier in mode.identifiers {
            let element = app.descendants(matching: .any)[identifier]
            if element.waitForExistence(timeout: 1) {
                element.tap()
                return
            }
        }
        attachHierarchy(app: app, name: "missing-stage-input-mode-\(mode.rawValue)")
        XCTFail("Missing stage input mode \(mode.rawValue)")
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

    private enum StageInputMode: String {
        case participant
        case director

        var identifiers: [String] {
            switch self {
            case .participant:
                ["chat.stageInputMode.participant", "Participant", "参与者", "bubble.left.and.bubble.right"]
            case .director:
                ["chat.stageInputMode.director", "Director", "导演", "megaphone"]
            }
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
