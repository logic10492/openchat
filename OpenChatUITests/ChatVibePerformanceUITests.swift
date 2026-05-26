import XCTest

final class ChatVibePerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_longVibeChatScrollPerformance() throws {
        let app = launchPerformanceApp()
        let timeline = app.scrollViews.firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 8))

        measure(
            metrics: [
                XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app),
            ],
            options: iterationOptions()
        ) {
            timeline.swipeUp(velocity: .fast)
            timeline.swipeUp(velocity: .fast)
            timeline.swipeDown(velocity: .fast)
            timeline.swipeDown(velocity: .fast)
        }
    }

    @MainActor
    func test_longVibeChatGenerationPerformance() throws {
        let app = launchPerformanceApp()
        let input = chatInput(app: app)
        XCTAssertTrue(input.waitForExistence(timeout: 8))

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app),
            ],
            options: iterationOptions()
        ) {
            input.tap()
            input.typeText("performance generation probe")
            app.buttons["chat.sendButton"].tap()
            XCTAssertTrue(
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Perf stream chunk 119")).firstMatch.waitForExistence(timeout: 12)
            )
        }
    }

    @MainActor
    private func launchPerformanceApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-chat-performance",
        ]
        app.launch()
        return app
    }

    private func iterationOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        return options
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
}
