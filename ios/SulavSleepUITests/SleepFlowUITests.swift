import XCTest

final class SleepFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func onboard(_ app: XCUIApplication) {
        app.launchArguments += ["-uitest-reset", "-uitest-mock-auth"]
        app.launch()

        app.buttons["Begin"].tap()
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Tester")
        app.buttons["Next"].tap()
        app.buttons["Next"].tap() // bedtime
        app.buttons["Next"].tap() // wake

        if app.buttons["Maybe later"].waitForExistence(timeout: 3) {
            app.buttons["Maybe later"].tap()
        } else if app.buttons["Start sleeping well"].waitForExistence(timeout: 3) {
            app.buttons["Start sleeping well"].tap()
        }

        // The auth gate: sign up with a mocked account so the flow reaches Home.
        let continueWithEmail = app.buttons["Continue with email"]
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: 5))
        continueWithEmail.tap()
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText("tester@example.com")
        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        passwordField.tap()
        passwordField.typeText("password123")
        app.buttons["Create account"].tap()

        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5))
    }

    func testSleepThenWakeReturnsHome() {
        let app = XCUIApplication()
        onboard(app)

        app.buttons["Sleep Now"].tap()
        let tapToWake = app.staticTexts["Tap to wake"]
        XCTAssertTrue(tapToWake.waitForExistence(timeout: 4), "Sleeping state should show Tap to wake")
        tapToWake.tap()
        XCTAssertTrue(app.buttons["Wake up"].waitForExistence(timeout: 4), "Sleeping state should show Wake up")

        app.buttons["Wake up"].tap()
        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 4), "Waking should return to Home")
    }

    func testReportsTabShowsAfterLoggingANight() {
        let app = XCUIApplication()
        onboard(app)

        // Log one real night.
        app.buttons["Sleep Now"].tap()
        let tapToWake = app.staticTexts["Tap to wake"]
        XCTAssertTrue(tapToWake.waitForExistence(timeout: 4))
        tapToWake.tap()
        XCTAssertTrue(app.buttons["Wake up"].waitForExistence(timeout: 4))
        app.buttons["Wake up"].tap()
        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 4))

        // Navigate to Reports.
        app.buttons["Reports"].tap()
        XCTAssertTrue(app.staticTexts["Reports"].waitForExistence(timeout: 4), "Reports screen should appear")
    }
}
