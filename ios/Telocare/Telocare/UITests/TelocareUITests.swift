import XCTest

final class TelocareUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUnauthenticatedLaunchShowsAuthScreen() {
        let app = configuredApp(authState: .unauthenticated)
        app.launch()

        XCTAssertTrue(app.textFields[UIID.authEmailInput].waitForExistence(timeout: 2))
        XCTAssertTrue(app.secureTextFields[UIID.authPasswordInput].exists)
    }

    func testSignInSuccessReachesDashboard() {
        let app = configuredApp(authState: .unauthenticated)
        app.launch()

        let emailField = app.textFields[UIID.authEmailInput]
        let passwordField = app.secureTextFields[UIID.authPasswordInput]
        XCTAssertTrue(emailField.waitForExistence(timeout: 2))
        emailField.tap()
        emailField.typeText("user@example.com")
        passwordField.tap()
        passwordField.typeText("Password123!")

        app.buttons[UIID.authSignInButton].tap()
        XCTAssertTrue(app.buttons[UIID.profileButton].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[UIID.guidedOutcomesCTA].waitForExistence(timeout: 2))
    }

    func testCreateAccountWithoutSessionShowsConfirmationStatus() {
        let app = configuredApp(
            authState: .unauthenticated,
            signUpNeedsConfirmation: true
        )
        app.launch()

        let emailField = app.textFields[UIID.authEmailInput]
        let passwordField = app.secureTextFields[UIID.authPasswordInput]
        XCTAssertTrue(emailField.waitForExistence(timeout: 2))
        emailField.tap()
        emailField.typeText("new@example.com")
        passwordField.tap()
        passwordField.typeText("Password123!")

        app.buttons[UIID.authCreateAccountButton].tap()

        let statusMessage = app.staticTexts[UIID.authStatusMessage]
        XCTAssertTrue(statusMessage.waitForExistence(timeout: 2))
        XCTAssertTrue(statusMessage.label.contains("Account created."))
    }

    func testGuidedFlowTransitionsToExploreMode() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)
        XCTAssertTrue(app.tabBars.buttons["Situation"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.buttons["Chat"].exists)
    }

    func testExploreChatTabIsReachable() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let chatTab = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 4))
        chatTab.tap()

        XCTAssertTrue(app.textFields[UIID.exploreChatInput].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons[UIID.exploreChatSendButton].exists)
    }

    func testOutcomesScreenDoesNotShowSaveButton() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        if app.buttons[UIID.guidedOutcomesCTA].waitForExistence(timeout: 1) {
            completeGuidedFlow(in: app)
        }

        let outcomesTab = app.tabBars.buttons["Outcomes"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        XCTAssertFalse(app.buttons[UIID.exploreMorningSaveButton].exists)
    }

    func testSituationGraphDoesNotHideTabBar() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        XCTAssertTrue(app.tabBars.buttons["Situation"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.webViews[UIID.graphWebView].waitForExistence(timeout: 2))
    }

    func testAuthenticatedGraphRendersAndHandlesTapSelection() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        app.buttons[UIID.guidedOutcomesCTA].tap()

        let graph = app.webViews[UIID.graphWebView]
        XCTAssertTrue(graph.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[UIID.graphSelectionText].waitForExistence(timeout: 2))

        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()

        let selection = app.staticTexts[UIID.graphSelectionText].label
        XCTAssertFalse(selection.isEmpty)
    }

    func testProfileSignOutReturnsToAuthScreen() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        app.buttons[UIID.profileButton].tap()
        XCTAssertTrue(app.otherElements[UIID.profileSheet].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[UIID.profileAccountEntry].exists)
        XCTAssertTrue(app.buttons[UIID.profileSettingsEntry].exists)
        XCTAssertTrue(app.buttons[UIID.profileSignOutEntry].exists)
        app.buttons[UIID.profileSignOutEntry].tap()
        XCTAssertTrue(app.textFields[UIID.authEmailInput].waitForExistence(timeout: 2))
    }

    private func configuredApp(
        authState: UITestAuthState,
        signUpNeedsConfirmation: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TELOCARE_USE_MOCK_SERVICES"] = "1"
        app.launchEnvironment["TELOCARE_UI_AUTH_STATE"] = authState.rawValue
        if signUpNeedsConfirmation {
            app.launchEnvironment["TELOCARE_SIGNUP_NEEDS_CONFIRMATION"] = "1"
        }
        return app
    }

    private func completeGuidedFlow(in app: XCUIApplication) {
        let outcomesButton = app.buttons[UIID.guidedOutcomesCTA]
        XCTAssertTrue(outcomesButton.waitForExistence(timeout: 4))
        outcomesButton.tap()

        let situationButton = app.buttons[UIID.guidedSituationCTA]
        XCTAssertTrue(situationButton.waitForExistence(timeout: 4))
        situationButton.tap()

        let doneButton = app.buttons[UIID.guidedDoneCTA]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
        doneButton.tap()
    }
}

private enum UITestAuthState: String {
    case authenticated
    case unauthenticated
}

private enum UIID {
    static let authEmailInput = "auth.email.input"
    static let authPasswordInput = "auth.password.input"
    static let authSignInButton = "auth.signin.button"
    static let authCreateAccountButton = "auth.createaccount.button"
    static let authStatusMessage = "auth.status.message"
    static let guidedOutcomesCTA = "guided.outcomes.cta"
    static let guidedSituationCTA = "guided.situation.cta"
    static let guidedDoneCTA = "guided.inputs.done"
    static let graphWebView = "graph.webview"
    static let graphSelectionText = "graph.selection.text"
    static let profileButton = "profile.open.button"
    static let profileSheet = "profile.sheet"
    static let profileAccountEntry = "profile.account.entry"
    static let profileSettingsEntry = "profile.settings.entry"
    static let profileSignOutEntry = "profile.signout.entry"
    static let exploreChatInput = "explore.chat.input"
    static let exploreChatSendButton = "explore.chat.send.button"
    static let exploreMorningSaveButton = "explore.outcomes.morning.save.button"
}
