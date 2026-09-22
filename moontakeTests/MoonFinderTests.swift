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
