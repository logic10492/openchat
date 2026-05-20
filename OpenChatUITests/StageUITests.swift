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
        if !directorMode.waitForExistence(timeout: 1) {
            let enableStage = app.buttons["stage.enableButton"].exists ? app.buttons["stage.enableButton"] : app.buttons["Enable Stage"]
            if !enableStage.waitForExistence(timeout: 5) {
                attachHierarchy(app: app, name: "missing-stage-enable")
                XCTFail("Missing Enable Stage button")
                return
            }
            enableStage.tap()
        }

        if !directorMode.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-director-mode")
            XCTFail("Missing Director Mode picker")
            return
        }
        directorMode.tap()
        tapOption("Agent", app: app)

        let addParticipant = app.descendants(matching: .any)["stage.addParticipantPicker"]
        if !addParticipant.waitForExistence(timeout: 5) {
            attachHierarchy(app: app, name: "missing-add-participant")
            XCTFail("Missing Add Participant picker")
            return
        }
        addParticipant.tap()
        tapOption("Io", app: app)

        XCTAssertTrue(app.staticTexts["Io"].waitForExistence(timeout: 5))
        let removeIo = app.buttons["stage.removeParticipant.Io"]
        XCTAssertTrue(removeIo.waitForExistence(timeout: 5))
        removeIo.tap()
        XCTAssertFalse(app.staticTexts["Io"].waitForExistence(timeout: 1))

        addParticipant.tap()
        tapOption("Io", app: app)
        XCTAssertTrue(app.staticTexts["Io"].waitForExistence(timeout: 5))

        app.buttons["chatSettings.doneButton"].tap()

        let rolePicker = app.descendants(matching: .any)["chat.inputRolePicker"]
        XCTAssertTrue(rolePicker.waitForExistence(timeout: 5))
        tapRole("chat.inputRole.director", labels: ["Director", "导演"], rolePicker: rolePicker, app: app)

        let input = app.textFields["chat.inputText"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Keep Io quiet.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertFalse(app.staticTexts["Keep Io quiet."].waitForExistence(timeout: 1))

        tapRole("chat.inputRole.participant", labels: ["Participant", "参与者"], rolePicker: rolePicker, app: app)
        input.tap()
        input.typeText("Mara, answer first.")
        app.buttons["chat.sendButton"].tap()

        XCTAssertTrue(app.staticTexts["Mara, answer first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI stage reply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mara"].waitForExistence(timeout: 5))
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
    private func tapRole(
        _ identifier: String,
        labels: [String],
        rolePicker: XCUIElement,
        app: XCUIApplication
    ) {
        let identified = app.buttons[identifier]
        if identified.waitForExistence(timeout: 1) {
            identified.tap()
            return
        }
        for label in labels {
            let button = rolePicker.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return
            }
        }
        for label in labels {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return
            }
        }
        attachHierarchy(app: app, name: "missing-role-\(identifier)")
        XCTFail("Missing input role \(identifier)")
    }

    @MainActor
    private func attachHierarchy(app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
