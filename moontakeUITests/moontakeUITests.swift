import XCTest
import CoreLocation

final class moontakeUITests: XCTestCase {
    // These tests exercise other camera features; onboarding has its own tests.
    private let completedTutorialArguments = [
        "-com.zizicici.moontake.tutorial.camera.version", "1",
        "-com.zizicici.moontake.tutorial.camera.seenTips",
        "(livePhoto, location, moonFinder, moonCalendar, album, settings)",
    ]
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTutorialAdvancesThroughCameraGesturesWithoutNextButton() throws {
#if targetEnvironment(simulator)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-com.zizicici.moontake.tutorial.camera.version", "0"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Spread or pinch two fingers to zoom."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Next"].exists)
        let preview = app.otherElements["camera.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.pinch(withScale: 1.3, velocity: 1)
        XCTAssertTrue(app.staticTexts["Tap your subject to focus."].waitForExistence(timeout: 5))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Drag the slider to fine-tune focus."].waitForExistence(timeout: 5))
        app.sliders["camera.focus"].adjust(toNormalizedSliderPosition: 0.7)
        XCTAssertTrue(app.staticTexts["Tap − to darken, + to brighten."].waitForExistence(timeout: 5))
        app.buttons["Lighten Image"].tap()
        XCTAssertTrue(app.staticTexts["Hold steady and tap the shutter to shoot."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].exists)
        // End using the system close button. Never take a photo in this test.
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["camera.more"].waitForExistence(timeout: 5))
#else
        throw XCTSkip("Gesture verification is confined to the simulator; never capture a photo")
#endif
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

    /// Preview/configuration only: never press the shutter or request microphone access.
    @MainActor
    func testLiveSoundDefaultsAndSilentToggleWithoutCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + completedTutorialArguments
        app.launch()
        let live = app.buttons["camera.livePhoto"]
        let sound = app.buttons["camera.livePhotoAudio"]
        let location = app.buttons["camera.location"]
        XCTAssertTrue(live.waitForExistence(timeout: 10))
        XCTAssertTrue(sound.exists)
        XCTAssertLessThanOrEqual(location.frame.maxX, sound.frame.minX)
        XCTAssertLessThanOrEqual(sound.frame.maxX, live.frame.minX)
        XCTAssertFalse(sound.isSelected, "The initial sound preference must be off")
#if !targetEnvironment(simulator)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: live)
        awaitReady(ready)
        XCTAssertFalse(live.isSelected, "Run with Live initially off, then restore it after verification")
        live.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: live)
        wait(for: [on], timeout: 10)
        XCTAssertFalse(sound.isSelected)
        XCTAssertTrue(sound.isEnabled)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Silent Live must not ask for microphone access")
        live.tap()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == false"), object: live)
        wait(for: [off], timeout: 10)
        XCTAssertFalse(sound.isEnabled)
#endif
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Location Live Sound controls"; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// Preview and location-name editing only; never press the shutter.
    @MainActor
    func testLocationNameEditingAndVisibilityWithoutCapture() throws {
#if targetEnvironment(simulator)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + completedTutorialArguments
        app.launch()
        defer { app.terminate() }
        let location = app.buttons["camera.location"]
        let name = app.buttons["camera.locationName"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        if location.isSelected {
            location.tap()
            app.buttons["不记录位置信息"].tap()
        }
        XCTAssertFalse(name.exists)
        // The simulator must grant the app location access before this test.
        location.tap()
        let enable = app.buttons["记录位置信息"]
        guard enable.waitForExistence(timeout: 3) else {
            throw XCTSkip("Grant simulator location access before running location editing regression")
        }
        enable.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.label, "位置信息")
        name.tap()
        let editor = app.alerts["自定义地名"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let text = "Marina Bay"
        editor.textFields.firstMatch.typeText(text)
        editor.buttons["好的"].tap()
        XCTAssertEqual(name.label, text)
        XCTAssertLessThanOrEqual(location.frame.maxX, name.frame.minX)
        XCTAssertLessThanOrEqual(name.frame.maxX, app.buttons["camera.livePhotoAudio"].frame.minX)
        location.tap()
        app.buttons["不记录位置信息"].tap()
        XCTAssertFalse(name.exists)
        location.tap()
        app.buttons["记录位置信息"].tap()
        XCTAssertEqual(name.label, text, "Switching location off must preserve the custom name")
        app.buttons["moonCalendar.open"].tap()
        XCTAssertTrue(app.buttons["moonCalendar.close"].waitForExistence(timeout: 5))
        app.buttons["moonCalendar.close"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Editable location with sound left of Live"
        attachment.lifetime = .keepAlways
        add(attachment)
        name.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.textFields.firstMatch.value as? String, text)
        editor.textFields.firstMatch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        editor.buttons["好的"].tap()
        XCTAssertEqual(name.label, "位置信息", "Clearing a name must leave the edit entry available")
        location.tap()
        app.buttons["不记录位置信息"].tap()
#else
        throw XCTSkip("Location editing regression uses the simulator")
#endif
    }

    /// Optional local simulator fixture; never acts on an unrelated pending capture.
    /// Stage a Live pair with this job UUID in Application Support/PendingLivePhotos.
    @MainActor
    func testPendingLivePhotoRecoveryWithoutCapture() throws {
#if targetEnvironment(simulator)
        // Old simulator fixtures can leave a Photos deletion confirmation open.
        // Decline it; this test never deletes Photos assets.
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let staleDeletion = system.alerts.firstMatch
        if staleDeletion.staticTexts.containing(NSPredicate(format: "label CONTAINS 'moontake' AND label CONTAINS 'delete'")).count > 0,
           staleDeletion.buttons["Don't Allow"].exists {
            staleDeletion.buttons["Don't Allow"].tap()
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + completedTutorialArguments
        app.launch()
        let alert = app.alerts["livePhoto.recovery.83EEBDCA-0C63-4795-9903-D20A379956F1"]
        guard alert.waitForExistence(timeout: 10) else { throw XCTSkip("No local recovery UI fixture staged") }
        XCTAssertTrue(alert.buttons["稍后"].exists)
        alert.buttons["重试保存"].tap()
        XCTAssertTrue(app.alerts["正在保存 Live 照片…"].waitForExistence(timeout: 10))
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.alerts)
        wait(for: [finished], timeout: 30)
        app.terminate()
        app.launch()
        XCTAssertFalse(alert.waitForExistence(timeout: 3), "A completed save must not be offered again")
#else
        throw XCTSkip("Recovery fixture writes are confined to the simulator")
#endif
    }

    @MainActor
    private func awaitReady(_ expectation: XCTestExpectation) { wait(for: [expectation], timeout: 15) }

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
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + completedTutorialArguments
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
