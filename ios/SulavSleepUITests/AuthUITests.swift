import XCTest

final class AuthUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "-uitest-mock-auth"]
        app.launch()
        return app
    }

    /// Runs the same onboarding steps as `OnboardingUITests`, ending right
    /// before the new auth gate.
    private func completeOnboarding(_ app: XCUIApplication, name: String = "Tester") {
        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()

        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        let maybeLater = app.buttons["Maybe later"]
        let startAnyway = app.buttons["Start sleeping well"]
        if maybeLater.waitForExistence(timeout: 3) {
            maybeLater.tap()
        } else if startAnyway.waitForExistence(timeout: 3) {
            startAnyway.tap()
        }
    }

    func testAuthScreenAppearsAfterOnboardingWithAllThreeOptions() {
        let app = launchFresh()
        completeOnboarding(app)

        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue with email"].exists)
        // The native Sign in with Apple button doesn't expose a stable
        // accessibility label across OS versions, so we only assert the two
        // Liquid-styled buttons directly.
    }

    func testManualEmailSignUpReachesHome() {
        let app = launchFresh()
        completeOnboarding(app)

        let continueWithEmail = app.buttons["Continue with email"]
        XCTAssertTrue(continueWithEmail.waitForExistence(timeout: 5))
        continueWithEmail.tap()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText("ada@example.com")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        passwordField.tap()
        passwordField.typeText("password123")

        app.buttons["Create account"].tap()

        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5), "Home should show after a successful mocked sign-up")
    }
}
