import XCTest

final class TelocareUIExplorerUITests: XCTestCase {
    func testCaptureExploreFlowScreens() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TELOCARE_USE_MOCK_SERVICES"] = "1"
        app.launchEnvironment["TELOCARE_UI_AUTH_STATE"] = "authenticated"
        app.launch()

        capture("01-guided-outcomes")

        if app.buttons["guided.outcomes.cta"].waitForExistence(timeout: 4) {
            app.buttons["guided.outcomes.cta"].tap()

            let situationButton = app.buttons["guided.situation.cta"]
            XCTAssertTrue(situationButton.waitForExistence(timeout: 4))
            capture("02-guided-situation")
            situationButton.tap()

            let doneButton = app.buttons["guided.inputs.done"]
            XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
            capture("03-guided-inputs")
            doneButton.tap()
        }

        let situationTab = app.tabBars.buttons["My Map"]
        XCTAssertTrue(situationTab.waitForExistence(timeout: 4))
        situationTab.tap()
        capture("04-explore-situation-collapsed")

        let editButton = app.buttons["explore.situation.edit.button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 2))
        editButton.tap()
        capture("05-explore-situation-options")

        let optionsDoneButton = app.buttons["Done"]
        XCTAssertTrue(optionsDoneButton.waitForExistence(timeout: 2))
        optionsDoneButton.tap()
        capture("06-explore-situation-after-options")

        let inputsTab = app.tabBars.buttons["Habits"]
        XCTAssertTrue(inputsTab.exists)
        inputsTab.tap()
        capture("07-explore-inputs")

        let outcomesTab = app.tabBars.buttons["Progress"]
        XCTAssertTrue(outcomesTab.exists)
        outcomesTab.tap()
        capture("08-explore-outcomes")

        let chatTab = app.tabBars.buttons["Guide"]
        XCTAssertTrue(chatTab.exists)
        chatTab.tap()
        XCTAssertTrue(app.textFields["explore.chat.input"].waitForExistence(timeout: 4))
        capture("09-explore-chat")
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
