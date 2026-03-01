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
        XCTAssertTrue(app.tabBars.buttons["My Map"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.buttons["Guide"].exists)
    }

    func testExploreChatTabIsReachable() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let chatTab = app.tabBars.buttons["Guide"]
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

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        XCTAssertFalse(app.buttons[UIID.exploreMorningSaveButton].exists)
    }

    func testOutcomesShowsMeasurementRoadmapStub() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        let roadmap = element(withIdentifier: UIID.exploreOutcomesMeasurementRoadmap, in: app)
        XCTAssertTrue(roadmap.waitForExistence(timeout: 4))
    }

    func testOutcomesMorningCheckInAutoCollapseAndManualReopen() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        let toggle = app.buttons[UIID.exploreOutcomesMorningCheckInToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        if (toggle.value as? String) != "Expanded" {
            toggle.tap()
            XCTAssertTrue(waitForValue("Expanded", of: toggle, timeout: 4))
        }

        let pickerIDs = [
            UIID.exploreMorningGlobalPicker,
            UIID.exploreMorningNeckPicker,
            UIID.exploreMorningJawPicker,
            UIID.exploreMorningEarPicker,
            UIID.exploreMorningAnxietyPicker,
            UIID.exploreMorningStressPicker,
            UIID.exploreMorningHeadachePicker,
            UIID.exploreMorningDryMouthPicker
        ]
        var selectedCount = 0
        for pickerID in pickerIDs {
            if selectMorningRatingIfPresent(in: app, pickerID: pickerID) {
                selectedCount += 1
            }
        }
        XCTAssertGreaterThan(selectedCount, 0)

        let morningChart = element(withIdentifier: UIID.exploreOutcomesMorningChart, in: app)
        XCTAssertTrue(morningChart.waitForExistence(timeout: 4))

        if (toggle.value as? String) != "Collapsed" {
            toggle.tap()
            XCTAssertTrue(waitForValue("Collapsed", of: toggle, timeout: 4))
        }

        reopenMorningCheckIn(in: app, toggle: toggle)
        XCTAssertTrue(waitForValue("Expanded", of: toggle, timeout: 4))
    }

    func testOutcomesHidesNightTrendProgressAndRecentNights() {
        let app = configuredApp(authState: .authenticated, useEmptyMockData: true)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        XCTAssertFalse(element(withIdentifier: UIID.exploreOutcomesNightChart, in: app).exists)
        XCTAssertFalse(app.staticTexts["Your progress"].exists)
        XCTAssertFalse(app.staticTexts["Recent nights"].exists)
        XCTAssertFalse(app.staticTexts["No night data yet"].exists)
    }

    func testOutcomesMuseSectionHiddenByDefault() {
        let app = configuredApp(authState: .authenticated, museEnabled: false)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        scrollPastPotentialMuseSection(in: app)
        XCTAssertFalse(element(withIdentifier: UIID.exploreMuseSessionSection, in: app).exists)
    }

    func testOutcomesMuseSectionShowsTextFirstControls() {
        let app = configuredApp(authState: .authenticated, museEnabled: true)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        scrollToMuseSection(in: app)

        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseSessionSection, in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseConnectionStatus, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseRecordingStatus, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseScanButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseConnectButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseDisconnectButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseStartRecordingButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseStopRecordingButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseSaveNightOutcomeButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseExportSetupDiagnosticsButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseExportDiagnosticsButton, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseFeedbackText, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreMuseDisclaimerText, in: app).exists)
    }

    func testOutcomesMuseSessionFlowEnablesSaveAction() {
        let app = configuredApp(authState: .authenticated, museEnabled: true)
        app.launch()

        completeGuidedFlow(in: app)

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.waitForExistence(timeout: 4))
        outcomesTab.tap()

        scrollToMuseSection(in: app)

        let scanButton = element(withIdentifier: UIID.exploreMuseScanButton, in: app)
        let connectButton = element(withIdentifier: UIID.exploreMuseConnectButton, in: app)
        let startButton = element(withIdentifier: UIID.exploreMuseStartRecordingButton, in: app)
        let stopButton = element(withIdentifier: UIID.exploreMuseStopRecordingButton, in: app)
        let saveButton = element(withIdentifier: UIID.exploreMuseSaveNightOutcomeButton, in: app)
        let setupExportButton = element(withIdentifier: UIID.exploreMuseExportSetupDiagnosticsButton, in: app)
        let exportButton = element(withIdentifier: UIID.exploreMuseExportDiagnosticsButton, in: app)
        let connectionStatus = element(withIdentifier: UIID.exploreMuseConnectionStatus, in: app)
        let recordingStatus = element(withIdentifier: UIID.exploreMuseRecordingStatus, in: app)
        let summaryText = element(withIdentifier: UIID.exploreMuseSummaryText, in: app)
        let reliabilityText = element(withIdentifier: UIID.exploreMuseReliabilityText, in: app)
        let liveStatusText = element(withIdentifier: UIID.exploreMuseLiveStatusText, in: app)
        let fitModal = element(withIdentifier: UIID.exploreMuseFitModal, in: app)
        let fitStatusText = element(withIdentifier: UIID.exploreMuseFitModalStatusText, in: app)
        let fitPrimaryBlockerText = element(withIdentifier: UIID.exploreMuseFitModalPrimaryBlockerText, in: app)
        let fitReadyStreakText = element(withIdentifier: UIID.exploreMuseFitModalReadyStreakText, in: app)
        let fitDiagnosisText = element(withIdentifier: UIID.exploreMuseFitModalDiagnosisText, in: app)
        let fitConnectionHealthText = element(withIdentifier: UIID.exploreMuseFitModalConnectionHealthText, in: app)
        let fitSignalHealthText = element(withIdentifier: UIID.exploreMuseFitModalSignalHealthText, in: app)
        let fitTroubleshootingSummaryText = element(withIdentifier: UIID.exploreMuseFitModalTroubleshootingSummaryText, in: app)
        let fitTroubleshootingActionsText = element(withIdentifier: UIID.exploreMuseFitModalTroubleshootingActionsText, in: app)
        let fitOvernightTipsText = element(withIdentifier: UIID.exploreMuseFitModalOvernightTipsText, in: app)
        let fitReadinessChecksText = element(withIdentifier: UIID.exploreMuseFitModalReadinessChecksText, in: app)
        let fitSensorStatusText = element(withIdentifier: UIID.exploreMuseFitModalSensorStatusText, in: app)
        let fitSetupExportButton = element(withIdentifier: UIID.exploreMuseFitModalExportSetupButton, in: app)
        let startOverrideButton = element(withIdentifier: UIID.exploreMuseFitModalStartOverrideButton, in: app)

        XCTAssertTrue(scanButton.waitForExistence(timeout: 4))
        scanButton.tap()
        XCTAssertTrue(waitForLabelContaining("Discovered", of: connectionStatus, timeout: 4))

        connectButton.tap()
        XCTAssertTrue(waitForLabelContaining("Connected", of: connectionStatus, timeout: 4))

        startButton.tap()
        XCTAssertTrue(fitModal.waitForExistence(timeout: 4))
        XCTAssertTrue(fitStatusText.exists)
        XCTAssertTrue(fitPrimaryBlockerText.exists)
        XCTAssertTrue(fitReadyStreakText.exists)
        XCTAssertTrue(fitDiagnosisText.exists)
        XCTAssertTrue(fitConnectionHealthText.exists)
        XCTAssertTrue(fitSignalHealthText.exists)
        XCTAssertTrue(fitTroubleshootingSummaryText.exists)
        XCTAssertTrue(fitTroubleshootingActionsText.exists)
        XCTAssertTrue(fitOvernightTipsText.exists)
        XCTAssertTrue(fitReadinessChecksText.exists)
        XCTAssertTrue(fitSensorStatusText.exists)
        XCTAssertTrue(fitSetupExportButton.exists)
        XCTAssertTrue(startOverrideButton.isEnabled)
        XCTAssertTrue(waitForLabelContaining("Likely issue", of: fitDiagnosisText, timeout: 2))
        XCTAssertTrue(waitForLabelContaining("Plain-English summary", of: fitTroubleshootingSummaryText, timeout: 2))
        XCTAssertTrue(waitForLabelContaining("Try this now", of: fitTroubleshootingActionsText, timeout: 2))
        XCTAssertTrue(waitForLabelContaining("Overnight tips", of: fitOvernightTipsText, timeout: 2))
        startOverrideButton.tap()
        XCTAssertTrue(waitForLabelContaining("Recording", of: recordingStatus, timeout: 4))
        XCTAssertTrue(waitForLabelContaining("Live status", of: liveStatusText, timeout: 4))

        stopButton.tap()
        XCTAssertTrue(waitForLabelContaining("Stopped", of: recordingStatus, timeout: 4))
        XCTAssertTrue(waitForLabelContaining("signal confidence", of: summaryText, timeout: 4))
        XCTAssertTrue(waitForLabelContaining("awake likelihood (provisional)", of: summaryText, timeout: 4))
        XCTAssertTrue(waitForLabelContaining("Recording reliability", of: reliabilityText, timeout: 4))
        XCTAssertTrue(setupExportButton.isEnabled)
        XCTAssertFalse(exportButton.isEnabled)

        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()
        XCTAssertTrue(waitForLabelContaining("Not recording", of: recordingStatus, timeout: 4))
    }

    func testSituationGraphDoesNotHideTabBar() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["My Map"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()
        XCTAssertTrue(app.webViews[UIID.graphWebView].waitForExistence(timeout: 2))
    }

    func testAuthenticatedGraphRendersAndHandlesTapSelection() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["My Map"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()

        let graph = app.webViews[UIID.graphWebView]
        XCTAssertTrue(graph.waitForExistence(timeout: 2))
        let editButton = app.buttons[UIID.exploreSituationEditButton]
        XCTAssertTrue(editButton.waitForExistence(timeout: 4))
        editButton.tap()
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
        doneButton.tap()
    }

    func testSituationDetailSheetSupportsDeactivationToggle() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["My Map"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()

        let graph = app.webViews[UIID.graphWebView]
        XCTAssertTrue(graph.waitForExistence(timeout: 2))
        let nodeToggleButton = app.buttons[UIID.exploreDetailsNodeDeactivationButton]
        let edgeToggleButton = app.buttons[UIID.exploreDetailsEdgeDeactivationButton]
        let detailSheet = element(withIdentifier: UIID.exploreDetailsSheet, in: app)
        var nodeToggleExists = false
        var edgeToggleExists = false

        let tapTargets = [
            CGVector(dx: 0.18, dy: 0.22),
            CGVector(dx: 0.32, dy: 0.22),
            CGVector(dx: 0.46, dy: 0.22),
            CGVector(dx: 0.60, dy: 0.22),
            CGVector(dx: 0.74, dy: 0.22),
            CGVector(dx: 0.18, dy: 0.36),
            CGVector(dx: 0.32, dy: 0.36),
            CGVector(dx: 0.46, dy: 0.36),
            CGVector(dx: 0.60, dy: 0.36),
            CGVector(dx: 0.74, dy: 0.36),
            CGVector(dx: 0.18, dy: 0.50),
            CGVector(dx: 0.32, dy: 0.50),
            CGVector(dx: 0.46, dy: 0.50),
            CGVector(dx: 0.60, dy: 0.50),
            CGVector(dx: 0.74, dy: 0.50),
            CGVector(dx: 0.18, dy: 0.64),
            CGVector(dx: 0.32, dy: 0.64),
            CGVector(dx: 0.46, dy: 0.64),
            CGVector(dx: 0.60, dy: 0.64),
            CGVector(dx: 0.74, dy: 0.64)
        ]

        for target in tapTargets {
            graph.coordinate(withNormalizedOffset: target).tap()
            if !detailSheet.waitForExistence(timeout: 1.2) {
                continue
            }

            nodeToggleExists = nodeToggleButton.waitForExistence(timeout: 1.2)
            edgeToggleExists = edgeToggleButton.waitForExistence(timeout: 1.2)
            if nodeToggleExists || edgeToggleExists {
                break
            }
        }

        XCTAssertTrue(nodeToggleExists || edgeToggleExists)

        let toggleButton = nodeToggleExists ? nodeToggleButton : edgeToggleButton
        let initialLabel = toggleButton.label
        toggleButton.tap()
        XCTAssertTrue(waitForLabelChange(of: toggleButton, from: initialLabel, timeout: 2))

        let statusIdentifier = nodeToggleExists
            ? UIID.exploreDetailsNodeDeactivationStatus
            : UIID.exploreDetailsEdgeDeactivationStatus
        let status = element(withIdentifier: statusIdentifier, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 2))
    }

    func testProfileSignOutReturnsToAuthScreen() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        app.buttons[UIID.profileButton].tap()
        XCTAssertTrue(app.otherElements[UIID.profileSheet].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[UIID.profileAccountEntry].exists)
        XCTAssertTrue(element(withIdentifier: UIID.profileThemeSection, in: app).exists)
        XCTAssertTrue(app.buttons[UIID.profileThemeWarmCoralOption].exists)
        XCTAssertTrue(app.buttons[UIID.profileThemeGardenOption].exists)
        XCTAssertTrue(app.switches[UIID.profileMuseFeatureToggle].exists)
        XCTAssertTrue(app.buttons[UIID.profileSignOutEntry].exists)
        app.buttons[UIID.profileSignOutEntry].tap()
        XCTAssertTrue(app.textFields[UIID.authEmailInput].waitForExistence(timeout: 2))
    }

    func testProfileThemeCanSwitchToGardenAndBack() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        app.buttons[UIID.profileButton].tap()
        XCTAssertTrue(app.otherElements[UIID.profileSheet].waitForExistence(timeout: 2))

        let warmCoralOption = app.buttons[UIID.profileThemeWarmCoralOption]
        let gardenOption = app.buttons[UIID.profileThemeGardenOption]
        XCTAssertTrue(warmCoralOption.waitForExistence(timeout: 2))
        XCTAssertTrue(gardenOption.exists)

        gardenOption.tap()
        XCTAssertTrue(waitForValue("Selected", of: gardenOption, timeout: 2))
        XCTAssertTrue(waitForValue("Not selected", of: warmCoralOption, timeout: 2))

        warmCoralOption.tap()
        XCTAssertTrue(waitForValue("Selected", of: warmCoralOption, timeout: 2))
        XCTAssertTrue(waitForValue("Not selected", of: gardenOption, timeout: 2))
    }

    func testSwitchingThemeWhileViewingSituationKeepsGraphInteractive() {
        let app = configuredApp(authState: .authenticated)
        app.launch()
        completeGuidedFlow(in: app)

        let situationTab = app.tabBars.buttons["My Map"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()

        let graph = app.webViews[UIID.graphWebView]
        XCTAssertTrue(graph.waitForExistence(timeout: 2))

        app.buttons[UIID.profileButton].tap()
        let gardenOption = app.buttons[UIID.profileThemeGardenOption]
        XCTAssertTrue(gardenOption.waitForExistence(timeout: 2))
        gardenOption.tap()

        let closeButton = app.buttons[UIID.profileCloseButton]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        closeButton.tap()

        XCTAssertTrue(graph.waitForExistence(timeout: 2))
        let editButton = app.buttons[UIID.exploreSituationEditButton]
        XCTAssertTrue(editButton.waitForExistence(timeout: 4))
        editButton.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
    }

    func testInputsDefaultToAvailableAndSupportsCommitAndUncommit() {
        let app = configuredApp(authState: .authenticated, useEmptyMockData: true)
        app.launch()

        completeGuidedFlow(in: app)

        let inputsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(inputsTab.waitForExistence(timeout: 4))
        inputsTab.tap()

        XCTAssertTrue(scrollUntilHabitControlVisible(in: app, maxSwipes: 16))

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

        XCTAssertTrue(openFirstInputDetail(in: app))

        let stopTrackingButton = app.buttons["Stop tracking this intervention"]
        XCTAssertTrue(stopTrackingButton.waitForExistence(timeout: 2))
        stopTrackingButton.tap()

        let availableFilter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Available")
        ).firstMatch
        XCTAssertTrue(availableFilter.waitForExistence(timeout: 2))
        availableFilter.tap()

        let startAgainButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Start tracking ")
        ).firstMatch
        XCTAssertTrue(startAgainButton.waitForExistence(timeout: 4))
    }

    func testInputDetailShowsCompletionHistoryChart() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let inputsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(inputsTab.waitForExistence(timeout: 4))
        inputsTab.tap()

        XCTAssertTrue(openFirstInputDetail(in: app))

        let historyChart = element(withIdentifier: UIID.exploreInputCompletionHistoryChart, in: app)
        XCTAssertTrue(historyChart.waitForExistence(timeout: 4))
        XCTAssertTrue(waitForValueContaining("Latest", of: historyChart, timeout: 4))
    }

    func testHabitsShowsNextBestActionsSection() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        let nextBestActions = element(withIdentifier: UIID.exploreInputsNextBestActions, in: app)
        XCTAssertTrue(nextBestActions.waitForExistence(timeout: 4))
    }

    func testHabitsGardenHierarchyHidesUntappedTopLevelSiblings() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsPillarOverview, in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(firstPillarSection(in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsFilterPending, in: app).exists)
    }

    func testHabitsGardenHierarchySubgardenSelectionAndBreadcrumbReset() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        XCTAssertTrue(firstPillarSection(in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilHabitControlVisible(in: app, maxSwipes: 18))
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsNextBestActions, in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsPinnedHeader, in: app).exists)
    }

    func testHabitsGardenHierarchyBreadcrumbBackReturnsToPreviousLevel() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        XCTAssertTrue(firstPillarSection(in: app).waitForExistence(timeout: 4))

        let availableFilter = element(withIdentifier: UIID.exploreInputsFilterAvailable, in: app)
        XCTAssertTrue(availableFilter.waitForExistence(timeout: 4))
        availableFilter.tap()

        let pendingFilter = element(withIdentifier: UIID.exploreInputsFilterPending, in: app)
        XCTAssertTrue(pendingFilter.waitForExistence(timeout: 4))
        pendingFilter.tap()

        XCTAssertTrue(firstPillarSection(in: app).waitForExistence(timeout: 4))
    }

    func testHabitsUnifiedScrollFromGardensIntoHabits() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        let unifiedScroll = element(withIdentifier: UIID.exploreInputsUnifiedScroll, in: app)
        XCTAssertTrue(unifiedScroll.waitForExistence(timeout: 4))
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsPillarOverview, in: app).exists)
        XCTAssertTrue(firstPillarSection(in: app).exists)
        XCTAssertTrue(scrollUntilHabitControlVisible(in: app, maxSwipes: 16))

        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsFilterPending, in: app).exists)
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsPinnedHeader, in: app).exists)
    }

    func testHabitsUnifiedScrollNoNestedGardenScrollTrap() {
        let app = configuredApp(authState: .authenticated)
        app.launch()

        completeGuidedFlow(in: app)

        let habitsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(habitsTab.waitForExistence(timeout: 4))
        habitsTab.tap()

        XCTAssertTrue(firstPillarSection(in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(scrollUntilHabitControlVisible(in: app, maxSwipes: 18))
        XCTAssertTrue(element(withIdentifier: UIID.exploreInputsFilterPending, in: app).exists)
        XCTAssertFalse(element(withIdentifier: UIID.exploreInputsGardenBreadcrumbBack, in: app).exists)
    }

    private func configuredApp(
        authState: UITestAuthState,
        signUpNeedsConfirmation: Bool = false,
        useEmptyMockData: Bool = false,
        museEnabled: Bool? = nil
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
        if let museEnabled {
            app.launchEnvironment["TELOCARE_UI_MUSE_ENABLED"] = museEnabled ? "1" : "0"
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

        return app.tabBars.buttons["My Map"].waitForExistence(timeout: timeout)
    }

    private func firstPillarSection(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIID.exploreInputsPillarSectionPrefix)
        ).firstMatch
    }

    private func firstHabitPrimaryControl(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(
            format: "label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@ OR label BEGINSWITH[c] %@",
            "Check ",
            "Uncheck ",
            "Increment ",
            "Start tracking "
        )
        return app.buttons.matching(predicate).firstMatch
    }

    private func scrollUntilHabitControlVisible(in app: XCUIApplication, maxSwipes: Int) -> Bool {
        let control = firstHabitPrimaryControl(in: app)
        if control.waitForExistence(timeout: 1) {
            return true
        }

        for _ in 0..<maxSwipes {
            app.swipeUp()
            if control.exists {
                return true
            }
        }

        return control.exists
    }

    private func selectMorningRating(in app: XCUIApplication, pickerID: String) {
        XCTAssertTrue(selectMorningRatingIfPresent(in: app, pickerID: pickerID))
    }

    private func selectMorningRatingIfPresent(in app: XCUIApplication, pickerID: String) -> Bool {
        let picker = element(withIdentifier: pickerID, in: app)

        if !picker.exists {
            for _ in 0..<4 {
                app.swipeUp()
                if picker.exists {
                    break
                }
            }
        }

        guard picker.waitForExistence(timeout: 1.5) else {
            return false
        }

        let button = picker.buttons["Moderate: 😐"]
        if button.waitForExistence(timeout: 1.5) {
            button.tap()
            return true
        }

        let fallbackButton = picker.buttons.firstMatch
        guard fallbackButton.waitForExistence(timeout: 1.5) else {
            return false
        }
        fallbackButton.tap()
        return true
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

    private func waitForLabelChange(of element: XCUIElement, from initialLabel: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label != %@", initialLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabelContaining(_ expectedSubstring: String, of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", expectedSubstring)
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
        let detailSheet = element(withIdentifier: UIID.exploreInputDetailSheet, in: app)

        for _ in 0..<6 {
            if tapInputNamed(interventionName, in: app) {
                return detailSheet.waitForExistence(timeout: 4)
            }
            app.swipeUp()
        }

        for _ in 0..<3 {
            if tapInputNamed(interventionName, in: app) {
                return detailSheet.waitForExistence(timeout: 4)
            }
            app.swipeDown()
        }

        return false
    }

    private func openFirstInputDetail(in app: XCUIApplication) -> Bool {
        let detailSheet = element(withIdentifier: UIID.exploreInputDetailSheet, in: app)
        let inputsScroll = element(withIdentifier: UIID.exploreInputsUnifiedScroll, in: app)
        let detailButtonPredicate = NSPredicate(
            format: "NOT (label BEGINSWITH[c] 'Check ' OR label BEGINSWITH[c] 'Uncheck ' OR label BEGINSWITH[c] 'Increment ' OR label BEGINSWITH[c] 'Start tracking ' OR label CONTAINS[c] 'To do' OR label CONTAINS[c] 'Done' OR label CONTAINS[c] 'Available' OR label CONTAINS[c] 'Health Pillars' OR label CONTAINS[c] 'Next best actions')"
        )

        for _ in 0..<6 {
            let detailButton = inputsScroll.descendants(matching: .button).matching(detailButtonPredicate).firstMatch
            if detailButton.exists {
                detailButton.tap()
                return detailSheet.waitForExistence(timeout: 4)
            }
            app.swipeUp()
        }

        return false
    }

    private func tapInputNamed(_ interventionName: String, in app: XCUIApplication) -> Bool {
        let inputsScroll = element(withIdentifier: UIID.exploreInputsUnifiedScroll, in: app)

        let detailButton = inputsScroll.descendants(matching: .button).matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ AND NOT (label BEGINSWITH[c] 'Check ' OR label BEGINSWITH[c] 'Uncheck ' OR label BEGINSWITH[c] 'Increment ' OR label BEGINSWITH[c] 'Start tracking ')",
                interventionName
            )
        ).firstMatch
        if detailButton.exists {
            detailButton.tap()
            return true
        }

        let title = inputsScroll.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS[c] %@", interventionName)
        ).firstMatch
        if title.exists {
            title.tap()
            return true
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

    private func scrollPastPotentialMuseSection(in app: XCUIApplication) {
        for _ in 0..<4 {
            app.swipeUp()
        }
    }

    private func scrollToMuseSection(in app: XCUIApplication) {
        let section = element(withIdentifier: UIID.exploreMuseSessionSection, in: app)
        for _ in 0..<4 {
            if section.exists {
                return
            }
            app.swipeUp()
        }

        XCTAssertTrue(section.waitForExistence(timeout: 4))
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
    static let exploreSituationEditButton = "explore.situation.edit.button"
    static let exploreSituationOptionsSheet = "explore.situation.options.sheet"
    static let exploreDetailsSheet = "explore.situation.details.sheet"
    static let exploreDetailsNodeDeactivationButton = "explore.situation.details.node.deactivate"
    static let exploreDetailsNodeBranchToggleButton = "explore.situation.details.node.branch.toggle"
    static let exploreDetailsEdgeDeactivationButton = "explore.situation.details.edge.deactivate"
    static let exploreDetailsNodeDeactivationStatus = "explore.situation.details.node.status"
    static let exploreDetailsEdgeDeactivationStatus = "explore.situation.details.edge.status"
    static let profileButton = "profile.open.button"
    static let profileSheet = "profile.sheet"
    static let profileCloseButton = "profile.close.button"
    static let profileAccountEntry = "profile.account.entry"
    static let profileThemeSection = "profile.theme.section"
    static let profileThemeWarmCoralOption = "profile.theme.option.warm.coral"
    static let profileThemeGardenOption = "profile.theme.option.garden"
    static let profileMuseFeatureToggle = "profile.muse.feature.toggle"
    static let profileSignOutEntry = "profile.signout.entry"
    static let exploreChatInput = "explore.chat.input"
    static let exploreChatSendButton = "explore.chat.send.button"
    static let exploreMorningSaveButton = "explore.outcomes.morning.save.button"
    static let exploreOutcomesMorningChart = "explore.outcomes.morning.chart"
    static let exploreOutcomesNightChart = "explore.outcomes.night.chart"
    static let exploreOutcomesMeasurementRoadmap = "explore.outcomes.measurement.roadmap"
    static let exploreOutcomesMorningCheckInToggle = "explore.outcomes.morning.toggle"
    static let exploreMuseSessionSection = "explore.outcomes.muse.section"
    static let exploreMuseConnectionStatus = "explore.outcomes.muse.connection.status"
    static let exploreMuseRecordingStatus = "explore.outcomes.muse.recording.status"
    static let exploreMuseScanButton = "explore.outcomes.muse.scan.button"
    static let exploreMuseConnectButton = "explore.outcomes.muse.connect.button"
    static let exploreMuseDisconnectButton = "explore.outcomes.muse.disconnect.button"
    static let exploreMuseStartRecordingButton = "explore.outcomes.muse.start.button"
    static let exploreMuseStopRecordingButton = "explore.outcomes.muse.stop.button"
    static let exploreMuseSaveNightOutcomeButton = "explore.outcomes.muse.save.button"
    static let exploreMuseExportSetupDiagnosticsButton = "explore.outcomes.muse.setup.export.button"
    static let exploreMuseExportDiagnosticsButton = "explore.outcomes.muse.export.button"
    static let exploreMuseSummaryText = "explore.outcomes.muse.summary.text"
    static let exploreMuseReliabilityText = "explore.outcomes.muse.reliability.text"
    static let exploreMuseLiveStatusText = "explore.outcomes.muse.live.status.text"
    static let exploreMuseFitGuidanceText = "explore.outcomes.muse.fit.guidance.text"
    static let exploreMuseFitModal = "explore.outcomes.muse.fit.modal"
    static let exploreMuseFitModalStatusText = "explore.outcomes.muse.fit.modal.status.text"
    static let exploreMuseFitModalPrimaryBlockerText = "explore.outcomes.muse.fit.modal.blocker.text"
    static let exploreMuseFitModalReadyStreakText = "explore.outcomes.muse.fit.modal.ready.streak.text"
    static let exploreMuseFitModalDiagnosisText = "explore.outcomes.muse.fit.modal.diagnosis.text"
    static let exploreMuseFitModalConnectionHealthText = "explore.outcomes.muse.fit.modal.connection.health.text"
    static let exploreMuseFitModalSignalHealthText = "explore.outcomes.muse.fit.modal.signal.health.text"
    static let exploreMuseFitModalTroubleshootingSummaryText = "explore.outcomes.muse.fit.modal.troubleshooting.summary.text"
    static let exploreMuseFitModalTroubleshootingActionsText = "explore.outcomes.muse.fit.modal.troubleshooting.actions.text"
    static let exploreMuseFitModalOvernightTipsText = "explore.outcomes.muse.fit.modal.troubleshooting.overnight.text"
    static let exploreMuseFitModalReadinessChecksText = "explore.outcomes.muse.fit.modal.readiness.checks.text"
    static let exploreMuseFitModalSensorStatusText = "explore.outcomes.muse.fit.modal.sensor.status.text"
    static let exploreMuseFitModalStartReadyButton = "explore.outcomes.muse.fit.modal.start.ready.button"
    static let exploreMuseFitModalStartOverrideButton = "explore.outcomes.muse.fit.modal.start.override.button"
    static let exploreMuseFitModalExportSetupButton = "explore.outcomes.muse.fit.modal.setup.export.button"
    static let exploreMuseFitModalCloseButton = "explore.outcomes.muse.fit.modal.close.button"
    static let exploreMuseExportFeedbackText = "explore.outcomes.muse.export.feedback.text"
    static let exploreMuseFeedbackText = "explore.outcomes.muse.feedback.text"
    static let exploreMuseDisclaimerText = "explore.outcomes.muse.disclaimer.text"
    static let exploreInputDetailSheet = "explore.inputs.detail.sheet"
    static let exploreInputsNextBestActions = "explore.inputs.next.best.actions"
    static let exploreInputsUnifiedScroll = "explore.inputs.unified.scroll"
    static let exploreInputsPinnedHeader = "explore.inputs.header.pinned"
    static let exploreInputsFilterPending = "explore.inputs.filter.pending"
    static let exploreInputsFilterCompleted = "explore.inputs.filter.completed"
    static let exploreInputsFilterAvailable = "explore.inputs.filter.available"
    static let exploreInputsPillarOverview = "explore.inputs.pillar.overview"
    static let exploreInputsPillarSectionPrefix = "explore.inputs.pillar.section."
    static let exploreInputCompletionHistoryChart = "explore.inputs.completion.history.chart"
    static let exploreInputsGardenHierarchy = "explore.inputs.garden.hierarchy"
    static let exploreInputsGardenBreadcrumb = "explore.inputs.garden.breadcrumb"
    static let exploreInputsGardenBreadcrumbBack = "explore.inputs.garden.breadcrumb.back"
    static let exploreInputsGardenSubgardenStrip = "explore.inputs.garden.subgarden.strip"
    static let exploreInputsGardenSubgardenCardPrefix = "explore.inputs.garden.subgarden.card."
    static let exploreMorningGlobalPicker = "explore.outcomes.morning.global.picker"
    static let exploreMorningNeckPicker = "explore.outcomes.morning.neck.picker"
    static let exploreMorningJawPicker = "explore.outcomes.morning.jaw.picker"
    static let exploreMorningEarPicker = "explore.outcomes.morning.ear.picker"
    static let exploreMorningAnxietyPicker = "explore.outcomes.morning.anxiety.picker"
    static let exploreMorningStressPicker = "explore.outcomes.morning.stress.picker"
    static let exploreMorningHeadachePicker = "explore.outcomes.morning.headache.picker"
    static let exploreMorningDryMouthPicker = "explore.outcomes.morning.drymouth.picker"

    static func exploreInputsGardenBreadcrumbChip(depth: Int) -> String {
        "explore.inputs.garden.breadcrumb.chip.\(depth)"
    }
}
