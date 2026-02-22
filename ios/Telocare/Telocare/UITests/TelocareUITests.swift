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
        XCTAssertTrue(waitForGuidedOrExploreRoot(in: app, timeout: 2))
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

    func testOutcomesMorningCheckInAutoCollapseAndManualReopen() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Outcomes"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        let toggle = app.buttons[UIID.exploreOutcomesMorningCheckInToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        if (toggle.value as? String) != "Expanded" {
            toggle.tap()
            XCTAssertTrue(waitForValue("Expanded", of: toggle, timeout: 4))
        }

        selectMorningRating(in: app, pickerID: UIID.exploreMorningGlobalPicker)
        selectMorningRating(in: app, pickerID: UIID.exploreMorningNeckPicker)
        selectMorningRating(in: app, pickerID: UIID.exploreMorningJawPicker)
        selectMorningRating(in: app, pickerID: UIID.exploreMorningEarPicker)
        selectMorningRating(in: app, pickerID: UIID.exploreMorningAnxietyPicker)
        selectMorningRating(in: app, pickerID: UIID.exploreMorningStressPicker)

        XCTAssertTrue(waitForValue("Collapsed", of: toggle, timeout: 4))

        let morningChart = element(withIdentifier: UIID.exploreOutcomesMorningChart, in: app)
        XCTAssertTrue(morningChart.waitForExistence(timeout: 4))
        XCTAssertTrue(waitForValueContaining("Expanded", of: morningChart, timeout: 4))

        reopenMorningCheckIn(in: app, toggle: toggle)
        XCTAssertTrue(waitForValueContaining("Compact", of: morningChart, timeout: 4))
    }

    func testOutcomesNightChartShowsPlaceholderWhenNoData() {
        let app = configuredApp(authState: .authenticated, useEmptyMockData: true)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Outcomes"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        XCTAssertTrue(element(withIdentifier: UIID.exploreOutcomesNightChart, in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["No night outcome data yet. This chart will populate when night outcomes are recorded."]
                .waitForExistence(timeout: 4)
        )
    }

    func testSituationGraphDoesNotHideTabBar() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["Situation"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()
        XCTAssertTrue(app.webViews[UIID.graphWebView].waitForExistence(timeout: 2))
    }

    func testAuthenticatedGraphRendersAndHandlesTapSelection() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["Situation"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()

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

    func testInputsDefaultToAvailableAndSupportsCommitAndUncommit() {
        let app = configuredApp(authState: .authenticated, useEmptyMockData: true)
        app.launch()

        completeGuidedFlow(in: app)

        let inputsTab = app.tabBars.buttons["Inputs"]
        XCTAssertTrue(inputsTab.waitForExistence(timeout: 4))
        inputsTab.tap()

        let startButtonQuery = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Start tracking ")
        )
        let startButton = startButtonQuery.firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 4))

        let startLabel = startButton.label
        let interventionName = startLabel.replacingOccurrences(of: "Start tracking ", with: "")
        startButton.tap()

        let todoFilter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "To do")
        ).firstMatch
        XCTAssertTrue(todoFilter.waitForExistence(timeout: 2))
        todoFilter.tap()

        let checkButton = app.buttons["Check \(interventionName)"]
        let incrementButton = app.buttons["Increment \(interventionName)"]
        let foundInTodo = checkButton.waitForExistence(timeout: 2) || incrementButton.waitForExistence(timeout: 2)
        XCTAssertTrue(foundInTodo)

        let interventionTitle = app.staticTexts[interventionName]
        XCTAssertTrue(interventionTitle.waitForExistence(timeout: 2))
        interventionTitle.tap()

        let stopTrackingButton = app.buttons["Stop tracking this intervention"]
        XCTAssertTrue(stopTrackingButton.waitForExistence(timeout: 2))
        stopTrackingButton.tap()

        let availableFilter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Available")
        ).firstMatch
        XCTAssertTrue(availableFilter.waitForExistence(timeout: 2))
        availableFilter.tap()

        let startAgainButton = app.buttons["Start tracking \(interventionName)"]
        XCTAssertTrue(startAgainButton.waitForExistence(timeout: 2))
    }

    func testInputDetailShowsCompletionHistoryChart() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let inputsTab = app.tabBars.buttons["Inputs"]
        XCTAssertTrue(inputsTab.waitForExistence(timeout: 4))
        inputsTab.tap()

        guard let interventionName = completeInterventionForHistoryAssertion(in: app) else {
            XCTFail("Expected at least one check or increment action in Inputs.")
            return
        }

        XCTAssertTrue(openInputDetail(named: interventionName, in: app))

        let historyChart = element(withIdentifier: UIID.exploreInputCompletionHistoryChart, in: app)
        XCTAssertTrue(historyChart.waitForExistence(timeout: 4))
        XCTAssertTrue(waitForValueContaining("Latest", of: historyChart, timeout: 4))
    }

    private func configuredApp(
        authState: UITestAuthState,
        signUpNeedsConfirmation: Bool = false,
        useEmptyMockData: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TELOCARE_USE_MOCK_SERVICES"] = "1"
        app.launchEnvironment["TELOCARE_UI_AUTH_STATE"] = authState.rawValue
        if signUpNeedsConfirmation {
            app.launchEnvironment["TELOCARE_SIGNUP_NEEDS_CONFIRMATION"] = "1"
        }
        if useEmptyMockData {
            app.launchEnvironment["TELOCARE_MOCK_EMPTY_USER_DATA"] = "1"
        }
        return app
    }

    private func completeGuidedFlow(in app: XCUIApplication) {
        let outcomesButton = app.buttons[UIID.guidedOutcomesCTA]
        if !outcomesButton.waitForExistence(timeout: 4) {
            XCTAssertTrue(waitForGuidedOrExploreRoot(in: app, timeout: 4))
            return
        }

        outcomesButton.tap()

        let situationButton = app.buttons[UIID.guidedSituationCTA]
        XCTAssertTrue(situationButton.waitForExistence(timeout: 4))
        situationButton.tap()

        let doneButton = app.buttons[UIID.guidedDoneCTA]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
        doneButton.tap()
    }

    private func waitForGuidedOrExploreRoot(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        if app.buttons[UIID.guidedOutcomesCTA].waitForExistence(timeout: timeout) {
            return true
        }

        return app.tabBars.buttons["Situation"].waitForExistence(timeout: timeout)
    }

    private func selectMorningRating(in app: XCUIApplication, pickerID: String) {
        let picker = element(withIdentifier: pickerID, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        let button = picker.buttons["Moderate: 😐"]
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
    }

    private func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForValue(_ expectedValue: String, of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValueContaining(_ expectedSubstring: String, of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", expectedSubstring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func interventionName(fromActionLabel label: String) -> String? {
        let prefixes = ["Check ", "Increment ", "Uncheck ", "Start tracking "]

        for prefix in prefixes where label.hasPrefix(prefix) {
            let name = String(label.dropFirst(prefix.count))
            return name.isEmpty ? nil : name
        }

        return nil
    }

    private func completeInterventionForHistoryAssertion(in app: XCUIApplication) -> String? {
        let checkButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check ")).firstMatch
        if checkButton.waitForExistence(timeout: 4),
           let interventionName = interventionName(fromActionLabel: checkButton.label) {
            checkButton.tap()
            let doneFilter = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Done")
            ).firstMatch
            if doneFilter.waitForExistence(timeout: 2) {
                doneFilter.tap()
            }
            return interventionName
        }

        let incrementButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Increment ")).firstMatch
        if incrementButton.waitForExistence(timeout: 4),
           let interventionName = interventionName(fromActionLabel: incrementButton.label) {
            incrementButton.tap()
            return interventionName
        }

        return nil
    }

    private func openInputDetail(named interventionName: String, in app: XCUIApplication) -> Bool {
        let detailButton = app.buttons.containing(.staticText, identifier: interventionName).firstMatch
        if detailButton.waitForExistence(timeout: 2) {
            detailButton.tap()
            return element(withIdentifier: UIID.exploreInputDetailSheet, in: app).waitForExistence(timeout: 2)
        }

        let namedButton = app.buttons[interventionName]
        if namedButton.waitForExistence(timeout: 2) {
            namedButton.tap()
            return element(withIdentifier: UIID.exploreInputDetailSheet, in: app).waitForExistence(timeout: 2)
        }

        let title = app.staticTexts[interventionName]
        if title.waitForExistence(timeout: 2) {
            title.tap()
            return element(withIdentifier: UIID.exploreInputDetailSheet, in: app).waitForExistence(timeout: 2)
        }

        return false
    }

    private func reopenMorningCheckIn(in app: XCUIApplication, toggle: XCUIElement) {
        let globalPicker = element(withIdentifier: UIID.exploreMorningGlobalPicker, in: app)
        if globalPicker.waitForExistence(timeout: 1) {
            return
        }

        for _ in 0..<3 {
            toggle.tap()
            if globalPicker.waitForExistence(timeout: 1.5) {
                return
            }
        }

        XCTAssertTrue(globalPicker.waitForExistence(timeout: 4))
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
    static let exploreOutcomesMorningChart = "explore.outcomes.morning.chart"
    static let exploreOutcomesNightChart = "explore.outcomes.night.chart"
    static let exploreOutcomesMorningCheckInToggle = "explore.outcomes.morning.toggle"
    static let exploreInputDetailSheet = "explore.inputs.detail.sheet"
    static let exploreInputCompletionHistoryChart = "explore.inputs.completion.history.chart"
    static let exploreMorningGlobalPicker = "explore.outcomes.morning.global.picker"
    static let exploreMorningNeckPicker = "explore.outcomes.morning.neck.picker"
    static let exploreMorningJawPicker = "explore.outcomes.morning.jaw.picker"
    static let exploreMorningEarPicker = "explore.outcomes.morning.ear.picker"
    static let exploreMorningAnxietyPicker = "explore.outcomes.morning.anxiety.picker"
    static let exploreMorningStressPicker = "explore.outcomes.morning.stress.picker"
}
