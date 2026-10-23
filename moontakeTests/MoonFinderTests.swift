import XCTest
import CoreMotion
import CoreLocation
import UIKit
import SkyKit
@testable import moontake

final class MoonFinderTests: XCTestCase {
    // Upright portrait device, rear camera pointing to true north at the horizon.
    private let facingNorth = CMRotationMatrix(m11: 0, m12: -1, m13: 0,
                                               m21: 0, m22: 0, m23: 1,
                                               m31: -1, m32: 0, m33: 0)

    @MainActor
    func testDirectionGuideWorksWithoutCameraForTurnsTiltAndAlignment() async throws {
        let view = MoonFinderView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        view.backgroundColor = .skyColor
        // UIVisualEffectView needs a window and a hierarchy snapshot to render its mask correctly.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        // Finish the window's appearance transition before sampling its first guidance state.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(view.cameraGeometry)
        let pitchedUp = CMRotationMatrix(m11: 0, m12: -1, m13: 0,
            m21: -sin(.pi / 4), m22: 0, m23: cos(.pi / 4),
            m31: -cos(.pi / 4), m32: 0, m33: -sin(.pi / 4))
        let cases: [(String, Double, Double, CMRotationMatrix, Double, Bool)] = [
            ("right", 30, 0, facingNorth, .pi / 2, false),
            ("left", 330, 0, facingNorth, -.pi / 2, false),
            ("up", 0, 30, facingNorth, 0, false),
            ("down", 0, 15, pitchedUp, .pi, false),
            ("behind", 180, 10, facingNorth, .pi / 2, false),
            ("aligned", 0, 4, facingNorth, 0, true)
        ]
        for (name, azimuth, altitude, attitude, rotation, aligned) in cases {
            let position = MoonPosition(azimuth: azimuth, altitude: altitude)
            view.update(MoonFinderState(status: .tracking, position: position,
                guidance: .calculate(position: position, attitude: attitude)))
            view.layoutIfNeeded()
            let indicator = try XCTUnwrap(element("moonFinder.direction", in: view))
            XCTAssertFalse(indicator.isHidden, name)
            XCTAssertEqual(indicator.center.x, view.bounds.midX, accuracy: 0.1)
            XCTAssertEqual(indicator.transform.a, cos(rotation), accuracy: 0.001)
            XCTAssertEqual(indicator.transform.b, sin(rotation), accuracy: 0.001)
            XCTAssertTrue(try XCTUnwrap(element("moonFinder.target", in: view)).isHidden)
            XCTAssertTrue(try XCTUnwrap(element("moonFinder.arrow", in: view)).isHidden)
            let title = try XCTUnwrap(element("moonFinder.status", in: view) as? UILabel)
            let key = aligned ? "moon_finder.direction.aligned.title"
                : name == "behind" ? "moon_finder.turn_around.title" : "moon_finder.tracking.title"
            XCTAssertEqual(title.text, String(localized: String.LocalizationValue(key)))
            XCTAssertNil(view.hitTest(indicator.center, with: nil))
            // Let the blur's text mask commit before capturing the rendered screen.
            try await Task.sleep(for: .milliseconds(100))
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "Camera-free direction: " + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testDirectionGuideSwitchesWithPreviewAndClearsWhenTrackingStops() throws {
        let view = MoonFinderView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        let position = MoonPosition(azimuth: 8, altitude: 8)
        let tracking = MoonFinderState(status: .tracking, position: position,
            guidance: .calculate(position: position, attitude: facingNorth))
        view.update(tracking)
        view.layoutIfNeeded()
        let indicator = try XCTUnwrap(element("moonFinder.direction", in: view))
        let target = try XCTUnwrap(element("moonFinder.target", in: view))
        XCTAssertFalse(indicator.isHidden)
        view.cameraGeometry = { [weak view] in view.map { ($0.bounds, 70, 1) } }
        view.update(tracking)
        view.layoutIfNeeded()
        XCTAssertTrue(indicator.isHidden)
        XCTAssertFalse(target.isHidden)
        view.cameraGeometry = nil
        view.update(tracking)
        view.layoutIfNeeded()
        XCTAssertFalse(indicator.isHidden)
        XCTAssertTrue(target.isHidden)
        for status: MoonFinderState.Status in [.locationDenied, .locating, .locationUnavailable,
            .calibrating, .sensorsUnavailable, .belowHorizon, .ephemerisUnavailable] {
            view.update(MoonFinderState(status: status))
            view.layoutIfNeeded()
            XCTAssertTrue(indicator.isHidden)
            XCTAssertTrue(target.isHidden)
            XCTAssertTrue(try XCTUnwrap(element("moonFinder.arrow", in: view)).isHidden)
        }
    }

    @MainActor private func element(_ id: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == id { return root }
        return root.subviews.lazy.compactMap { self.element(id, in: $0) }.first
    }

    func testSensorSelectionFallsBackToMagneticButNeverAnArbitraryHeading() {
        let all: CMAttitudeReferenceFrame = [.xTrueNorthZVertical, .xMagneticNorthZVertical, .xArbitraryZVertical]
        XCTAssertEqual(MoonFinderManager.preferredReferenceFrame(available: all, failed: []), .xTrueNorthZVertical)
        XCTAssertEqual(MoonFinderManager.preferredReferenceFrame(available: all, failed: .xTrueNorthZVertical), .xMagneticNorthZVertical)
        XCTAssertEqual(MoonFinderManager.preferredReferenceFrame(available: .xMagneticNorthZVertical, failed: []), .xMagneticNorthZVertical)
        XCTAssertNil(MoonFinderManager.preferredReferenceFrame(available: .xArbitraryZVertical, failed: []))
        XCTAssertNil(MoonFinderManager.preferredReferenceFrame(available: all, failed: [.xTrueNorthZVertical, .xMagneticNorthZVertical]))
    }

    @MainActor
    func testMagneticGuideNeverProjectsATargetOrClaimsAlignment() throws {
        let view = MoonFinderView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        view.cameraGeometry = { [weak view] in view.map { ($0.bounds, 70, 1) } }
        let position = MoonPosition(azimuth: 0, altitude: 4)
        let guidance = MoonGuidance.calculate(position: position, attitude: facingNorth)
        XCTAssertTrue(guidance.isAligned)
        view.update(MoonFinderState(status: .tracking, position: position, guidance: guidance, usesMagneticNorth: true))
        view.layoutIfNeeded()
        XCTAssertFalse(try XCTUnwrap(element("moonFinder.direction", in: view)).isHidden)
        XCTAssertTrue(try XCTUnwrap(element("moonFinder.target", in: view)).isHidden)
        XCTAssertTrue(try XCTUnwrap(element("moonFinder.arrow", in: view)).isHidden)
        let title = try XCTUnwrap(element("moonFinder.status", in: view) as? UILabel)
        XCTAssertEqual(title.text, String(localized: "moon_finder.magnetic.title"))
        view.update(MoonFinderState(status: .tracking, position: position, guidance: guidance))
        view.layoutIfNeeded()
        XCTAssertTrue(try XCTUnwrap(element("moonFinder.direction", in: view)).isHidden)
        XCTAssertFalse(try XCTUnwrap(element("moonFinder.target", in: view)).isHidden)
    }

    @MainActor
    func testAROverlayTargetArrowAndTouchPassthrough() throws {
        let view = MoonFinderView(frame: CGRect(x: 0, y: 0, width: 390, height: 650))
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)
        view.cameraGeometry = { [weak view] in view.map { ($0.bounds, 70, 1) } }
        func element(_ id: String, in root: UIView) -> UIView? {
            if root.accessibilityIdentifier == id { return root }
            return root.subviews.lazy.compactMap { element(id, in: $0) }.first
        }
        for (name, azimuth) in [("AR target in view", 8.0), ("AR turn right", 80.0)] {
            let position = MoonPosition(azimuth: azimuth, altitude: 8)
            view.update(MoonFinderState(status: .tracking, position: position,
                guidance: .calculate(position: position, attitude: facingNorth)))
            view.layoutIfNeeded()
            let target = try XCTUnwrap(element("moonFinder.target", in: view))
            let arrow = try XCTUnwrap(element("moonFinder.arrow", in: view))
            XCTAssertEqual(target.isHidden, azimuth == 80)
            XCTAssertEqual(arrow.isHidden, azimuth == 8)
            XCTAssertNil(view.hitTest(CGPoint(x: 195, y: 325), with: nil))
            let screenshot = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        view.update(MoonFinderState(status: .locationDenied))
        view.layoutIfNeeded()
        let settings = try XCTUnwrap(element("moonFinder.settings", in: view))
        let point = settings.convert(CGPoint(x: settings.bounds.midX, y: settings.bounds.midY), to: view)
        XCTAssertTrue(view.hitTest(point, with: nil) === settings)
        XCTAssertNil(view.hitTest(CGPoint(x: 195, y: 100), with: nil))
        XCTAssertTrue(try XCTUnwrap(element("moonFinder.target", in: view)).isHidden)
        XCTAssertTrue(try XCTUnwrap(element("moonFinder.arrow", in: view)).isHidden)
    }

    func testRejectsStaleInvalidAndVeryInaccurateLocations() {
        let now = Date()
        func location(accuracy: Double = 100, age: TimeInterval = 0, latitude: Double = 1.35) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 103.8),
                       altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
                       timestamp: now.addingTimeInterval(-age))
        }
        XCTAssertTrue(MoonFinderManager.isUsable(location(), now: now))
        XCTAssertTrue(MoonFinderManager.isUsable(location(accuracy: 5000), now: now))
        XCTAssertFalse(MoonFinderManager.isUsable(location(accuracy: -1), now: now))
        XCTAssertFalse(MoonFinderManager.isUsable(location(accuracy: 20000), now: now))
        XCTAssertFalse(MoonFinderManager.isUsable(location(age: 120), now: now))
        XCTAssertFalse(MoonFinderManager.isUsable(location(latitude: 91), now: now))
    }

    @MainActor
    func testFinderStopIsIdempotentAndDoesNotChangePhotoGeotagPreference() {
        let initialPreference = Location.shared.manualDisable
        let manager = MoonFinderManager()
        manager.stop()
        manager.stop()
        XCTAssertFalse(manager.isActive)
        XCTAssertEqual(Location.shared.manualDisable, initialPreference)
    }

    @MainActor
    func testPhotoGeotagOptOutSurvivesReinitialization() {
        let key = UserDefaults.Custom.LocationMetadataDisabled.rawValue
        let originalValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let originalValue {
                UserDefaults.standard.set(originalValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let photoLocation = Location()
        photoLocation.manual(disable: true)
        let restoredLocation = Location()
        XCTAssertTrue(restoredLocation.manualDisable)
        XCTAssertNil(restoredLocation.location)
    }
}
