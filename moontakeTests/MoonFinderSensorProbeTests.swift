import XCTest
import CoreMotion
import CoreLocation
import UIKit
@testable import moontake

@MainActor
final class MoonFinderSensorProbeTests: XCTestCase {
    func testFinderTracksOnDeviceWithoutCamera() async throws {
        guard ProcessInfo.processInfo.environment["MOONTAKE_SENSOR_PROBE"] == "1" else {
            throw XCTSkip("Opt-in device sensor regression")
        }
        let manager = MoonFinderManager()
        let ready = expectation(description: "Device direction guidance")
        var result: MoonFinderState?
        var statuses = [String]()
        manager.onUpdate = { state in
            let status = String(describing: state.status)
            if statuses.last != status { statuses.append(status) }
            if result == nil, state.status == .tracking || state.status == .belowHorizon {
                result = state
                ready.fulfill()
            }
        }
        manager.start()
        defer { manager.stop() }
        await fulfillment(of: [ready], timeout: 20)
        print("MOONTAKE FINDER STATES: \(statuses)")
        let state = try XCTUnwrap(result)
        guard state.status != .belowHorizon else { throw XCTSkip("The Moon is currently below the local horizon") }
        XCTAssertNotNil(state.guidance)
        if ProcessInfo.processInfo.environment["MOONTAKE_EXPECT_MAGNETIC_GUIDANCE"] == "1" {
            XCTAssertTrue(state.usesMagneticNorth)
        }
        print("MOONTAKE FINDER TRACKING magnetic=\(state.usesMagneticNorth)")
        let view = MoonFinderView()
        view.backgroundColor = .skyColor
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        view.update(state)
        window.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Device finder without camera"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAvailableGuidanceSources() async throws {
        guard ProcessInfo.processInfo.environment["MOONTAKE_SENSOR_PROBE"] == "1" else {
            throw XCTSkip("Opt-in device sensor diagnostics")
        }
        let manager = CMMotionManager()
        let location = CLLocationManager()
        let observer = HeadingProbe()
        location.delegate = observer
        location.headingFilter = kCLHeadingFilterNone
        var reports = ["motion=\(manager.isDeviceMotionAvailable) heading=\(CLLocationManager.headingAvailable()) frames=\(CMMotionManager.availableAttitudeReferenceFrames().rawValue) locationAuthorization=\(location.authorizationStatus.rawValue)"]
        if location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways {
            location.startUpdatingLocation()
            location.startUpdatingHeading()
        }
        defer {
            manager.stopDeviceMotionUpdates()
            location.stopUpdatingLocation()
            location.stopUpdatingHeading()
        }
        manager.deviceMotionUpdateInterval = 0.1
        for (name, frame): (String, CMAttitudeReferenceFrame) in [
            ("true", .xTrueNorthZVertical), ("magnetic", .xMagneticNorthZVertical), ("relative", .xArbitraryZVertical)
        ] {
            guard CMMotionManager.availableAttitudeReferenceFrames().contains(frame) else {
                reports.append("\(name): unavailable")
                continue
            }
            var samples = 0
            var lastAccuracy = -10
            var errors = Set<String>()
            manager.startDeviceMotionUpdates(using: frame, to: .main) { sample, error in
                if let sample {
                    samples += 1
                    lastAccuracy = Int(sample.magneticField.accuracy.rawValue)
                }
                if let error = error as NSError? { errors.insert("\(error.domain):\(error.code)") }
            }
            try await Task.sleep(for: .seconds(3))
            manager.stopDeviceMotionUpdates()
            reports.append("\(name): samples=\(samples) magneticAccuracy=\(lastAccuracy) errors=\(errors.sorted())")
        }
        reports.append("headingSamples=\(observer.samples) trueHeadingValid=\(observer.trueHeadingValid) accuracy=\(observer.accuracy) errors=\(observer.errors)")
        let report = reports.joined(separator: "\n")
        print("MOONTAKE SENSOR PROBE\n" + report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Moon finder sensor availability"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class HeadingProbe: NSObject, CLLocationManagerDelegate {
    var samples = 0
    var trueHeadingValid = false
    var accuracy = -1.0
    var errors = Set<String>()
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        samples += 1
        trueHeadingValid = heading.trueHeading >= 0
        accuracy = heading.headingAccuracy
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let error = error as NSError
        errors.insert("\(error.domain):\(error.code)")
    }
}
