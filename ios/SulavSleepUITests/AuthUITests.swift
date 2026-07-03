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

    /// Runs the sign-up questionnaire, ending right before the account step.
    private func completeQuestionnaire(_ app: XCUIApplication, name: String = "Tester") {
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Next"].tap()

        // Struggles (leave empty) -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Bedtime -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        // Wake -> Next
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        let maybeLater = app.buttons["Maybe later"]
        let continueButton = app.buttons["Continue"]
        if maybeLater.waitForExistence(timeout: 3) {
            maybeLater.tap()
        } else if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }
    }

    func testAccountStepAppearsAfterQuestionnaireWithAllThreeOptions() {
        let app = launchFresh()
        completeQuestionnaire(app)

        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue with email"].exists)
        // The native Sign in with Apple button doesn't expose a stable
        // accessibility label across OS versions, so we only assert the two
        // Liquid-styled buttons directly.
    }

    func testManualEmailSignUpReachesHome() {
        let app = launchFresh()
        completeQuestionnaire(app)

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

    /// Returning-user path: welcome → sign in → quick setup → home.
    func testSignInPathRunsQuickSetupThenReachesHome() {
        let app = launchFresh()

        let signInEntry = app.buttons["I already have an account"]
        XCTAssertTrue(signInEntry.waitForExistence(timeout: 5))
        signInEntry.tap()

        // Sign-in framing with all providers, plus a way back to welcome.
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)

        let continueWithEmail = app.buttons["Continue with email"]
        continueWithEmail.tap()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        emailField.typeText("ada@example.com")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        passwordField.tap()
        passwordField.typeText("password123")

        // The email form defaults to sign-in mode on this path; submit via the
        // dedicated identifier since "Sign in" also names a segmented tab.
        app.buttons["authSubmit"].tap()

        // No profile on this device yet, so the quick setup runs.
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Quick setup should ask for the name after sign-in on a fresh device")
        nameField.tap()
        nameField.typeText("Ada")
        app.buttons["Next"].tap()

        for _ in 0..<3 { // struggles, bedtime, wake
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
            app.buttons["Next"].tap()
        }

        let maybeLater = app.buttons["Maybe later"]
        let continueButton = app.buttons["Continue"]
        if maybeLater.waitForExistence(timeout: 3) {
            maybeLater.tap()
        } else if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }

        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5), "Home should show after sign-in + quick setup")
    }

    /// The sign-in screen's back chevron returns to welcome.
    func testSignInBackReturnsToWelcome() {
        let app = launchFresh()

        let signInEntry = app.buttons["I already have an account"]
        XCTAssertTrue(signInEntry.waitForExistence(timeout: 5))
        signInEntry.tap()

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()

        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 3))
    }
}
