import UIKit
import XCTest
import StoreKitTest
import TipKit
@testable import moontake

@available(iOS 17.0, *)
@MainActor
final class CameraTutorialTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var window: UIWindow?
    private var previousWindow: UIWindow?
    private var storeSession: SKTestSession?
    private var progress: CameraTutorialProgress { CameraTutorialProgress(defaults: defaults) }

    override func setUpWithError() throws {
        suite = "moontake.tutorial.tests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        storeSession = try SKTestSession(contentsOf: XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "Memberships", withExtension: "storekit")))
        storeSession?.disableDialogs = true
    }

    override func tearDownWithError() throws {
        closeCamera()
        defaults.removePersistentDomain(forName: suite)
    }

    func testFirstRunUsesNativeTipsInOrderAndCompletionSurvivesRelaunch() async throws {
        let camera = try await openCamera()
        let expected: [CameraTutorialStep] = [.zoom, .tapFocus, .focus, .exposure, .capture]
        for step in expected {
            let guide = try await waitForTip(in: camera, step: step)
            XCTAssertFalse(guide.isTip)
            XCTAssertFalse(step.instruction.hasPrefix("tutorial.camera."))
            XCTAssertTrue(guide.popoverController is TipUIPopoverViewController)
            XCTAssertNil(guide.currentTip.message, "Only one sentence, no small-print description")
            XCTAssertTrue(guide.currentTip.actions.isEmpty, "No navigation or confirmation buttons")
            XCTAssertTrue(progress.shouldPresent)
            let popover = try XCTUnwrap(guide.popoverController)
            let frame = popover.view.convert(popover.view.bounds, to: guide.view)
            let source = try XCTUnwrap(guide.targetRects?(step, guide.view).last)
            XCTAssertFalse(frame.insetBy(dx: 2, dy: 2).intersects(source), "Tip must not cover its control: \(step)")
            try saveSnapshot("tutorial-" + step.rawValue)
            let controls = try XCTUnwrap(guide.interactionViews?(step))
            XCTAssertFalse(controls.isEmpty)
            XCTAssertEqual(popover.popoverPresentationController?.passthroughViews, controls)
            XCTAssertNil(guide.view.hitTest(CGPoint(x: guide.view.bounds.midX, y: guide.view.bounds.midY), with: nil))
            try perform(step, on: camera)
        }
        await waitUntil { self.guide(in: camera) == nil }
        XCTAssertFalse(progress.shouldPresent)
        XCTAssertEqual(progress.unseenTips.count, 6)
        camera.viewDidAppear(false)
        XCTAssertNil(guide(in: camera), "No extra tip in the first session")
        closeCamera()
        let reopened = try await openCamera()
        let tip = try await waitForTip(in: reopened)
        XCTAssertTrue(tip.isTip)
        XCTAssertFalse(progress.shouldPresent)
    }

    func testSystemCloseAndSettingsReplayReturnToExistingCamera() async throws {
        let camera = try await openCamera()
        let first = try await waitForTip(in: camera)
        let firstID = first.currentTip.id
        first.currentTip.invalidate(reason: .tipClosed)
        await waitUntil { self.guide(in: camera) == nil }
        XCTAssertFalse(progress.shouldPresent)
        try tap("camera.more", in: camera.view)
        await waitUntil { camera.presentedViewController != nil && camera.presentedViewController?.isBeingPresented == false }
        let navigation = try XCTUnwrap(camera.presentedViewController as? UINavigationController)
        let more = try XCTUnwrap(navigation.topViewController)
        let item = try XCTUnwrap([more.navigationItem.leftBarButtonItem, more.navigationItem.rightBarButtonItem]
            .compactMap { $0 }.first { $0.accessibilityIdentifier == "settings.tutorial" })
        XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item, for: nil))
        let replay = try await waitForTip(in: camera, step: .zoom)
        XCTAssertTrue(window?.rootViewController === camera)
        XCTAssertFalse(replay.isTip)
        XCTAssertEqual(replay.steps, [.zoom, .tapFocus, .focus, .exposure, .capture])
        XCTAssertNotEqual(replay.currentTip.id, firstID, "Replay must work after a native tip was invalidated")
        replay.finish()
        await waitUntil { self.guide(in: camera) == nil }
        XCTAssertEqual(progress.unseenTips.count, 6)
        XCTAssertFalse(try XCTUnwrap(find("camera.more", in: camera.view)).accessibilityElementsHidden)
    }

    func testOneRandomTipPerLaunchAndEachTipOnlyOnce() async throws {
        progress.complete()
        var seen: Set<CameraTutorialStep> = []
        for index in 0..<CameraTutorialStep.tips.count {
            let camera = try await openCamera()
            let tip = try await waitForTip(in: camera)
            XCTAssertTrue(tip.isTip)
            XCTAssertEqual(tip.steps.count, 1)
            XCTAssertTrue(CameraTutorialStep.tips.contains(tip.currentStep))
            XCTAssertTrue(seen.insert(tip.currentStep).inserted)
            await waitUntil { !self.progress.unseenTips.contains(tip.currentStep) }
            if index > 0 { // Terminate before acknowledgment on the first launch.
                tip.currentTip.invalidate(reason: .tipClosed)
                await waitUntil { self.guide(in: camera) == nil }
                camera.viewDidAppear(false)
                XCTAssertNil(guide(in: camera))
            }
            closeCamera()
        }
        XCTAssertEqual(seen, Set(CameraTutorialStep.tips))
        let camera = try await openCamera()
        XCTAssertNil(guide(in: camera))
        XCTAssertTrue(progress.unseenTips.isEmpty)
    }

    func testWaitsForBothPermissionDecisions() async throws {
        let camera = try await openCamera(waitForPermissions: true)
        XCTAssertNil(guide(in: camera))
        camera.cameraPermissionAuthorized = .denied
        XCTAssertNil(guide(in: camera))
        camera.addPhotoPermissionAuthorized = .denied
        _ = try await waitForTip(in: camera)
        XCTAssertTrue(progress.shouldPresent)
    }

    func testLiveTipDoesNotEnableLiveOrMicrophoneAndUsesNewPosition() async throws {
        progress.complete()
        CameraTutorialStep.tips.filter { $0 != .livePhoto }.forEach { progress.recordTipShown($0) }
        let keys = [UserDefaults.Custom.LivePhoto.rawValue, UserDefaults.Custom.LivePhotoAudio.rawValue]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) as? Bool }
        let camera = try await openCamera()
        let tip = try await waitForTip(in: camera, step: .livePhoto)
        let live = try XCTUnwrap(find("camera.livePhoto", in: camera.view))
        let sound = try XCTUnwrap(find("camera.livePhotoAudio", in: camera.view))
        let location = try XCTUnwrap(find("camera.location", in: camera.view))
        XCTAssertLessThanOrEqual(location.frame.maxX, sound.frame.minX)
        XCTAssertTrue(sound.isHidden)
        XCTAssertEqual(sound.frame.maxX, live.frame.minX, accuracy: 0.5)
        XCTAssertEqual(live.frame.maxX, camera.view.bounds.maxX - 6, accuracy: 0.5)
        try saveSnapshot("tutorial-livePhoto")
        tip.currentTip.invalidate(reason: .tipClosed)
        await waitUntil { self.guide(in: camera) == nil }
        XCTAssertEqual(keys.map { UserDefaults.standard.object(forKey: $0) as? Bool }, before)
        try saveSnapshot("tutorial-camera")
    }

    func testInterruptedWalkthroughCanStartAgain() async throws {
        var camera = try await openCamera()
        let first = try await waitForTip(in: camera)
        let firstID = first.currentTip.id
        try perform(.zoom, on: camera)
        _ = try await waitForTip(in: camera, step: .tapFocus)
        closeCamera()
        XCTAssertTrue(progress.shouldPresent)
        camera = try await openCamera()
        let restarted = try await waitForTip(in: camera, step: .zoom)
        XCTAssertNotEqual(restarted.currentTip.id, firstID)
        XCTAssertTrue(progress.shouldPresent)
    }

    func testMoonToolsOpenWithoutCameraOrPhotoPermissions() async throws {
        progress.complete()
        CameraTutorialStep.tips.forEach { progress.recordTipShown($0) }
        let camera = try await openCamera()
        XCTAssertEqual(camera.cameraPermissionAuthorized, .denied)
        XCTAssertEqual(camera.addPhotoPermissionAuthorized, .denied)
        let finder = try XCTUnwrap(find("moonFinder.toggle", in: camera.view) as? UIButton)
        XCTAssertTrue(finder.isEnabled)
        let finderCenter = finder.convert(CGPoint(x: finder.bounds.midX, y: finder.bounds.midY), to: camera.view)
        let finderHit = camera.view.hitTest(finderCenter, with: nil)
        XCTAssertTrue(finderHit === finder || finderHit?.isDescendant(of: finder) == true,
                      "The permission overlay must not intercept the finder button")
        let geotagDisabled = Location.shared.manualDisable
        finder.sendActions(for: .touchUpInside)
        let panel = try XCTUnwrap(find("moonFinder.panel", in: camera.view))
        XCTAssertFalse(panel.isHidden)
        XCTAssertEqual(finder.accessibilityLabel, String(localized: "moon_finder.close"))
        if Location.shared.authorizationStatus() == .denied {
            XCTAssertFalse(try XCTUnwrap(find("moonFinder.settings", in: panel)).isHidden)
            XCTAssertTrue(try XCTUnwrap(find("moonFinder.coordinates", in: panel)).isHidden)
        }
        camera.showPermissionViewIfNeeded()
        XCTAssertFalse(panel.isHidden, "Refreshing denied permissions must not dismiss the finder")
        finder.sendActions(for: .touchUpInside)
        XCTAssertTrue(panel.isHidden)
        XCTAssertEqual(Location.shared.manualDisable, geotagDisabled)
        let button = try XCTUnwrap(find("moonCalendar.open", in: camera.view) as? UIButton)
        XCTAssertTrue(button.isEnabled)
        let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: camera.view)
        let hit = camera.view.hitTest(center, with: nil)
        XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true,
                      "The permission overlay must not intercept the calendar button")
        button.sendActions(for: .touchUpInside)
        await waitUntil { camera.presentedViewController?.isBeingPresented == false }
        let navigation = try XCTUnwrap(camera.presentedViewController as? UINavigationController)
        XCTAssertTrue(navigation.topViewController is MoonCalendarViewController)
    }

    func testWrongActionsAndCancelledPinchDoNotAdvanceAndSliderWaitsForRelease() async throws {
        let camera = try await openCamera()
        let guide = try await waitForTip(in: camera, step: .zoom)
        camera.plusShutterScale()
        let cancelled = TutorialPinchGesture()
        cancelled.testState = .cancelled
        cancelled.scale = 1.2
        camera.handlePinchToZoomRecognizer(cancelled)
        XCTAssertEqual(guide.currentStep, .zoom)
        try perform(.zoom, on: camera)
        _ = try await waitForTip(in: camera, step: .tapFocus)
        try perform(.tapFocus, on: camera)
        _ = try await waitForTip(in: camera, step: .focus)
        let slider = TutorialTrackingSlider()
        slider.value = 0.7
        camera.lensPositionValueChanged(slider)
        XCTAssertEqual(guide.currentStep, .focus, "Do not change tips while a finger is dragging")
        let realSlider = try XCTUnwrap(find("camera.focus", in: camera.view) as? UISlider)
        realSlider.sendActions(for: .touchUpInside)
        _ = try await waitForTip(in: camera, step: .exposure)
        XCTAssertTrue(progress.shouldPresent)
    }

    private func perform(_ step: CameraTutorialStep, on camera: CameraViewController) throws {
        switch step {
        case .zoom:
            let pinch = TutorialPinchGesture()
            pinch.scale = 1.25
            camera.handlePinchToZoomRecognizer(pinch)
        case .tapFocus:
            camera.focusTap(TutorialTapGesture())
        case .focus:
            let slider = try XCTUnwrap(find("camera.focus", in: camera.view) as? UISlider)
            slider.value = 0.5
            slider.sendActions(for: .valueChanged)
        case .exposure:
            camera.plusShutterScale()
        case .capture:
            // Simulate the accepted capture event without invoking the shutter or hardware.
            camera.didPerformTutorialAction(.capture)
        default: XCTFail("Unexpected basic step")
        }
    }

    private func openCamera(waitForPermissions: Bool = false) async throws -> TutorialTestCamera {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.keyWindow
        let camera = TutorialTestCamera(tutorialProgress: progress)
        camera.waitForPermissions = waitForPermissions
        let newWindow = UIWindow(windowScene: scene)
        window = newWindow
        newWindow.rootViewController = camera
        newWindow.makeKeyAndVisible()
        await waitUntil { UIApplication.shared.applicationState == .active }
        camera.view.layoutIfNeeded()
        return camera
    }

    private func closeCamera() {
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        previousWindow?.makeKeyAndVisible()
        previousWindow = nil
    }

    private func waitForTip(in camera: CameraViewController, step: CameraTutorialStep? = nil) async throws -> TutorialsViewController {
        await waitUntil {
            guard let guide = self.guide(in: camera), let popover = guide.popoverController else { return false }
            return (step == nil || guide.currentStep == step) && popover.viewIfLoaded?.window != nil
                && !popover.isBeingPresented && !popover.isBeingDismissed
        }
        return try XCTUnwrap(guide(in: camera))
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        await fulfillment(of: [expectation], timeout: 8)
    }

    private func guide(in camera: CameraViewController) -> TutorialsViewController? {
        camera.children.compactMap { $0 as? TutorialsViewController }.first
    }

    private func find(_ id: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        return view.subviews.lazy.compactMap { self.find(id, in: $0) }.first
    }

    private func tap(_ id: String, in view: UIView) throws {
        let control = try XCTUnwrap(find(id, in: view) as? UIControl)
        XCTAssertTrue(control.isEnabled)
        control.sendActions(for: .touchUpInside)
    }

    private func saveSnapshot(_ name: String) throws {
        let window = try XCTUnwrap(window)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try image.pngData()?.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class TutorialTestCamera: CameraViewController {
    var waitForPermissions = false
    override func checkCameraPermissions() {
        if !waitForPermissions { cameraPermissionAuthorized = .denied }
    }
    override func checkPhotoPremissions() {
        if !waitForPermissions { addPhotoPermissionAuthorized = .denied }
    }
    override func setupAndStartCaptureSession() {}
    override func initializeMotionManager() {}
}

@MainActor
private final class TutorialPinchGesture: UIPinchGestureRecognizer {
    var testState: UIGestureRecognizer.State = .ended
    override var state: UIGestureRecognizer.State {
        get { testState }
        set { testState = newValue }
    }
}

@MainActor
private final class TutorialTapGesture: UITapGestureRecognizer {
    override var state: UIGestureRecognizer.State {
        get { .ended }
        set {}
    }
}

@MainActor
private final class TutorialTrackingSlider: UISlider {
    override var isTracking: Bool { true }
}
