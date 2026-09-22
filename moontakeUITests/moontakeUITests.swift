import XCTest

final class moontakeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMorePageOpensAndISOSelectionPersists() {
        let app = launchApp()
        app.buttons["More"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Upgrade to Pro to unlock:"].exists)
        app.tables.staticTexts["ISO"].tap()
        XCTAssertTrue(app.navigationBars["ISO Options"].waitForExistence(timeout: 5))
        app.tables.staticTexts["100"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        let isoCell = app.tables.cells.containing(.staticText, identifier: "ISO").firstMatch
        XCTAssertTrue(isoCell.staticTexts["100"].exists)
        app.terminate()
        app.launch()
        app.buttons["More"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tables.cells.containing(.staticText, identifier: "ISO").firstMatch.staticTexts["100"].exists)
    }

    @MainActor
    func testAlbumOpensFromCamera() {
        let app = launchApp()
        app.buttons["Album"].tap()
        XCTAssertTrue(app.navigationBars["Album"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.collectionViews.firstMatch.exists)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            // A simulator has no camera; deny permissions and exercise navigation/settings.
            let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' AND label CONTAINS[c] 't'")).firstMatch
            if deny.exists {
                deny.tap()
                return true
            }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 10))
        return app
    }
}
