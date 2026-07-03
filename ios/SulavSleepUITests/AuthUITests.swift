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

        // Wake -> Next, which advances to the account step (the final step).
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
        app.buttons["Next"].tap()
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

        // The sign-in email form's submit button; use the dedicated identifier.
        app.buttons["authSubmit"].tap()

        // No profile on this device yet, so the quick setup runs.
        let nameField = app.textFields["Your name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Quick setup should ask for the name after sign-in on a fresh device")
        nameField.tap()
        nameField.typeText("Ada")
        app.buttons["Next"].tap()

        for _ in 0..<2 { // struggles, bedtime -> wake
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3))
            app.buttons["Next"].tap()
        }

        // No account step on the quick-setup path, so the wake step is last and
        // its button commits onboarding.
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()

        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5), "Home should show after sign-in + quick setup")
    }

    /// Signing out lands on the standalone sign-in screen (the account is
    /// already made), with no cross-link back to sign-up.
    func testSignOutLandsOnSignIn() {
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
        XCTAssertTrue(app.buttons["Sleep Now"].waitForExistence(timeout: 5))

        app.buttons["Settings"].tap()
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 3))
        signOut.tap()

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5), "Sign-out should land on the sign-in screen")
        XCTAssertFalse(app.buttons["authFramingToggle"].exists, "There is no sign-up cross-link on the sign-in screen")
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
