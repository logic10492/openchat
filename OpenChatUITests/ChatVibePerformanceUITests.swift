import XCTest

final class ChatVibePerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_longVibeChatScrollPerformance() throws {
        let app = launchPerformanceApp(messageCount: 1_000)
        let timeline = chatTimeline(app: app)
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
        let app = launchPerformanceApp(messageCount: 1_000)
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
            XCTAssertTrue(waitForPerformanceGenerationCompletion(app: app), app.debugDescription)
        }
    }

    @MainActor
    func test_ultraLongVibeChatScrollPerformance_3000Messages() throws {
        let app = launchPerformanceApp(messageCount: 3_000)
        let timeline = chatTimeline(app: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 12))

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
    func test_extremeLongVibeChatScrollPerformance_10000Messages() throws {
        let app = launchPerformanceApp(messageCount: 10_000)
        let timeline = chatTimeline(app: app)
        XCTAssertTrue(timeline.waitForExistence(timeout: 16))

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
    private func launchPerformanceApp(messageCount: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-chat-performance",
            "--ui-testing-chat-performance-count",
            "\(messageCount)",
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

    @MainActor
    private func chatTimeline(app: XCUIApplication) -> XCUIElement {
        let collection = app.collectionViews["chat.timeline.collectionView"]
        if collection.waitForExistence(timeout: 1) {
            return collection
        }
        return app.scrollViews.firstMatch
    }

    @MainActor
    private func waitForPerformanceGenerationCompletion(app: XCUIApplication) -> Bool {
        let timeline = app.collectionViews["chat.timeline.collectionView"]
        if timeline.waitForExistence(timeout: 1) {
            let predicate = NSPredicate(format: "value == %@", "chat.performanceGenerationComplete")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: timeline)
            if XCTWaiter.wait(for: [expectation], timeout: 24) == .completed {
                return true
            }
        }

        let cell = app.cells["chat.performanceGenerationComplete"]
        if cell.waitForExistence(timeout: 1) {
            return true
        }
        return app.descendants(matching: .any)["chat.performanceGenerationComplete"].waitForExistence(timeout: 1)
    }
}
