import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset"]
        app.launch()
        return app
    }

    func testOnboardingFlowReachesHome() {
        let app = launchFresh()

        // Intro
        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5), "Onboarding intro should show a Begin button")
        begin.tap()

        // Name
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Tester")
        app.buttons["Next"].tap()

        // Bedtime (leave default) -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Wake (leave default) -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Health step: decline to avoid the system permission sheet.
        let maybeLater = app.buttons["Maybe later"]
        let startAnyway = app.buttons["Start sleeping well"]
        if maybeLater.waitForExistence(timeout: 3) {
            maybeLater.tap()
        } else if startAnyway.waitForExistence(timeout: 3) {
            startAnyway.tap()
        }

        // Home
        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5), "Home should show Sleep Now after onboarding")
        XCTAssertTrue(app.staticTexts["Tester"].exists, "The greeting should show the entered name")
    }
}
