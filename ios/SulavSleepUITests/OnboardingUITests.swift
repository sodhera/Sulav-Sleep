import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "-uitest-mock-auth"]
        app.launch()
        return app
    }

    func testSignUpPathReachesHome() {
        let app = launchFresh()

        // Welcome: two paths — sign-up questionnaire or returning-user sign-in.
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "Welcome should offer Get started")
        XCTAssertTrue(app.buttons["I already have an account"].exists, "Welcome should offer a sign-in path")
        getStarted.tap()

        // Name
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Tester")
        app.buttons["Next"].tap()

        // Struggles: multi-select, optional. Pick one to exercise selection.
        let phoneInBed = app.buttons["Phone in bed"]
        XCTAssertTrue(phoneInBed.waitForExistence(timeout: 3), "Struggles step should list options")
        phoneInBed.tap()
        app.buttons["Next"].tap()

        // Bedtime (leave default) -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Wake (leave default) -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Health step: decline to avoid the system permission sheet.
        let maybeLater = app.buttons["Maybe later"]
        let continueButton = app.buttons["Continue"]
        if maybeLater.waitForExistence(timeout: 3) {
            maybeLater.tap()
        } else if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }

        // Account step closes the sign-up path (see AuthUITests for dedicated
        // coverage of the auth screen itself).
        let continueWithEmail = app.buttons["Continue with email"]
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: 5), "Account step should appear after the questionnaire")
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

        // Home
        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5), "Home should show Sleep Now after sign-up")
        XCTAssertTrue(app.staticTexts["Tester"].exists, "The greeting should show the entered name")
    }

    func testBackFromFirstQuestionReturnsToWelcome() {
        let app = launchFresh()

        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 3), "Back from the first question should return to welcome")
    }
}
