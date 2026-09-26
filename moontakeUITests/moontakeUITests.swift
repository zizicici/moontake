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
    func testMoonCalendarNavigationSelectionAndClose() {
        let app = launchApp()
        let entry = app.buttons["moonCalendar.open"]
        let finder = app.buttons["moonFinder.toggle"]
        XCTAssertTrue(entry.exists)
        XCTAssertEqual(entry.frame.width, 44, accuracy: 1)
        XCTAssertEqual(entry.frame.height, 44, accuracy: 1)
        XCTAssertGreaterThan(entry.frame.midX, app.frame.midX)
        XCTAssertEqual(entry.frame.minY, finder.frame.minY, accuracy: 1)
        let cameraAttachment = XCTAttachment(screenshot: app.screenshot())
        cameraAttachment.name = "Moon calendar entry"
        cameraAttachment.lifetime = .keepAlways
        add(cameraAttachment)
        finder.tap()
        entry.tap()
        XCTAssertTrue(app.staticTexts["moonCalendar.phase"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["moonFinder.panel"].exists)
        let originalMonth = app.staticTexts["moonCalendar.month"].label
        let monthFrame = app.staticTexts["moonCalendar.month"].frame
        app.buttons["moonCalendar.day.15"].tap()
        XCTAssertTrue(app.buttons["moonCalendar.day.15"].isSelected)
        let illumination = app.staticTexts["moonCalendar.illumination"]
        XCTAssertTrue(illumination.label.range(of: #"[0-9]+\.[0-9]% → [0-9]+\.[0-9]%"#, options: .regularExpression) != nil)
        for _ in 0..<3 {
            app.buttons["moonCalendar.today"].tap()
            XCTAssertTrue(app.staticTexts["moonCalendar.phase"].exists)
            XCTAssertEqual(app.staticTexts["moonCalendar.month"].label, originalMonth)
            XCTAssertEqual(app.staticTexts["moonCalendar.month"].frame, monthFrame)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Moon calendar"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["moonCalendar.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(finder.label, "Find Moon")
    }

    @MainActor
    func testMoonCalendarRequiresMembershipForOtherMonths() {
        let app = launchApp()
        app.buttons["moonCalendar.open"].tap()
        XCTAssertTrue(app.staticTexts["moonCalendar.phase"].waitForExistence(timeout: 15))
        let currentMonth = app.staticTexts["moonCalendar.month"].label
        for direction in ["next", "previous"] {
            app.buttons["moonCalendar.\(direction)"].tap()
            XCTAssertTrue(app.buttons["moonCalendar.unlock"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["moonCalendar.lockedMessage"].exists)
            XCTAssertFalse(app.buttons["moonCalendar.day.1"].exists)
            XCTAssertFalse(app.staticTexts["moonCalendar.phase"].exists)
            XCTAssertFalse(app.navigationBars["More"].exists)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", currentMonth),
                                                     object: app.staticTexts["moonCalendar.month"])
            wait(for: [changed], timeout: 10)
            app.buttons["moonCalendar.unlock"].tap()
            XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Upgrade to Pro to unlock:"].exists)
            XCTAssertTrue(app.staticTexts["- Browse lunar phases in any month"].exists)
            dismissMembership(in: app, title: "More")
            XCTAssertTrue(app.buttons["moonCalendar.unlock"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["moonCalendar.phase"].exists)
            app.buttons["moonCalendar.today"].tap()
            XCTAssertTrue(app.staticTexts["moonCalendar.phase"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["moonCalendar.month"].label, currentMonth)
            XCTAssertFalse(app.buttons["moonCalendar.unlock"].exists)
        }
    }

    @MainActor
    func testMoonCalendarChineseLayout() {
        let app = launchApp(language: "zh-Hans")
        app.buttons["moonCalendar.open"].tap()
        XCTAssertTrue(app.staticTexts["moonCalendar.phase"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["月历"].exists)
        XCTAssertFalse(app.staticTexts["moonCalendar.nextFullMoon"].label.contains("·"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Moon calendar Chinese"
        attachment.lifetime = .keepAlways
        add(attachment)
        let currentMonth = app.staticTexts["moonCalendar.month"].label
        app.buttons["moonCalendar.next"].tap()
        XCTAssertTrue(app.buttons["moonCalendar.unlock"].waitForExistence(timeout: 5))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", currentMonth),
                                                 object: app.staticTexts["moonCalendar.month"])
        wait(for: [changed], timeout: 10)
        XCTAssertTrue(app.staticTexts["购买 Pro，查看任意月份"].exists)
        let locked = XCTAttachment(screenshot: app.screenshot())
        locked.name = "Moon calendar locked Chinese"
        locked.lifetime = .keepAlways
        add(locked)
        app.buttons["moonCalendar.unlock"].tap()
        XCTAssertTrue(app.navigationBars["更多"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["- 查看任意月份的月相"].exists)
        let promotion = XCTAttachment(screenshot: app.screenshot())
        promotion.name = "Moon calendar membership Chinese"
        promotion.lifetime = .keepAlways
        add(promotion)
        dismissMembership(in: app, title: "更多")
        XCTAssertTrue(app.buttons["moonCalendar.unlock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["moonCalendar.phase"].exists)
        let returned = XCTAttachment(screenshot: app.screenshot())
        returned.name = "Moon calendar locked after settings Chinese"
        returned.lifetime = .keepAlways
        add(returned)
    }

    @MainActor
    private func dismissMembership(in app: XCUIApplication, title: String) {
        let bar = app.navigationBars[title]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: bar)
        wait(for: [dismissed], timeout: 5)
        XCTAssertTrue(app.buttons["moonCalendar.unlock"].isHittable)
    }

    @MainActor
    private func launchApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
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
        XCTAssertTrue(app.buttons["moonCalendar.open"].waitForExistence(timeout: 10))
        return app
    }
}
