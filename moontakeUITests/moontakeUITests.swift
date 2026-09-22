import XCTest
import CoreLocation

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
    func testMoonFinderEntryPermissionAndClose() {
        XCUIApplication().resetAuthorizationStatus(for: .location)
        let app = launchApp()
        let toggle = app.buttons["moonFinder.toggle"]
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.frame.width, 44, accuracy: 1)
        XCTAssertEqual(toggle.frame.height, 44, accuracy: 1)
        XCTAssertLessThan(toggle.frame.midX, app.frame.midX)
        XCTAssertLessThan(toggle.frame.midY, app.frame.midY)
        toggle.tap()
        let panel = app.otherElements["moonFinder.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        // Trigger the permission interruption monitor if this is a first launch.
        app.staticTexts["moonFinder.status"].tap()
        XCTAssertTrue(app.buttons["moonFinder.settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["moonFinder.status"].label, "Enable Location")
        XCTAssertFalse(app.staticTexts["moonFinder.coordinates"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Moon finder — location denied"
        attachment.lifetime = .keepAlways
        add(attachment)
        toggle.tap()
        XCTAssertFalse(panel.exists)
        XCTAssertEqual(toggle.label, "Find Moon")
    }

    @MainActor
    func testMoonFinderReceivesLocationWithoutCompass() throws {
#if targetEnvironment(simulator)
        guard #available(iOS 16.4, *) else {
            throw XCTSkip("Simulated location requires iOS 16.4")
        }
        XCUIApplication().resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 1.3521, longitude: 103.8198))
        let app = launchApp()
        let monitor = addUIInterruptionMonitor(withDescription: "Finder location permission") { alert in
            let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS 'While Using'")).firstMatch
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        defer {
            removeUIInterruptionMonitor(monitor)
            app.terminate()
            app.resetAuthorizationStatus(for: .location)
            XCUIDevice.shared.location = nil
        }
        app.buttons["moonFinder.toggle"].tap()
        app.staticTexts["moonFinder.status"].tap()
        let coordinates = app.staticTexts["moonFinder.coordinates"]
        XCTAssertTrue(coordinates.waitForExistence(timeout: 15))
        XCTAssertTrue(coordinates.label.contains("Azimuth"))
        XCTAssertTrue(coordinates.label.contains("Altitude"))
        let status = app.staticTexts["moonFinder.status"].label
        XCTAssertTrue(["Direction guidance unavailable", "Moon below the horizon"].contains(status), status)
        XCTAssertFalse(app.buttons["moonFinder.settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Moon finder — simulated GPS without compass"
        attachment.lifetime = .keepAlways
        add(attachment)
#else
        throw XCTSkip("This case verifies the simulator's missing-compass fallback")
#endif
    }

    @MainActor
    func testMoonFinderStopsWhenOpeningSettingsOrBackgrounding() {
        let app = launchApp()
        let toggle = app.buttons["moonFinder.toggle"]
        toggle.tap()
        app.buttons["More"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["moonFinder.panel"].exists)
        app.terminate()
        app.launch()
        toggle.tap()
        XCTAssertTrue(app.otherElements["moonFinder.panel"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["moonFinder.panel"].exists)
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
