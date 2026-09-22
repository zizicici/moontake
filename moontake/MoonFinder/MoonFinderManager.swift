import CoreLocation
import CoreMotion
import SkyKit

struct MoonFinderState {
    enum Status {
        case ephemerisUnavailable, locating, locationDenied, locationUnavailable, sensorsUnavailable, calibrating, tracking, belowHorizon
    }
    let status: Status
    var position: MoonPosition?
    var guidance: MoonGuidance?
}

/// Owns sampling only while the finder is open. Its location request is independent
/// of Location.manualDisable, which controls GPS metadata saved with photos.
final class MoonFinderManager: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((MoonFinderState) -> Void)?
    private(set) var isActive = false
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var location: CLLocation?
    private var motion: CMDeviceMotion?
    private var motionReceivedAt: Date?
    private var timer: Timer?
    private var locationFailed = false
    private var motionFailed = false
    private var cachedPosition: MoonPosition?
    private var calculatedAt: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Keep timestamps fresh even when the observer stands still.
        locationManager.distanceFilter = kCLDistanceFilterNone
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.showsDeviceMovementDisplay = true
    }

    deinit {
        timer?.invalidate()
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
    }

    func start() {
        guard !isActive else { return }
        // Initialize the photo-location preference before global location
        // authorization can change as a result of this feature's request.
        _ = Location.shared
        isActive = true
        locationFailed = false
        motionFailed = false
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        updateAuthorization()
    }

    func stop() {
        isActive = false
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
        location = nil
        motion = nil
        motionReceivedAt = nil
        cachedPosition = nil
        calculatedAt = nil
    }

    private func updateAuthorization() {
        guard isActive else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            onUpdate?(MoonFinderState(status: .locating))
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            refresh()
        case .denied, .restricted:
            locationManager.stopUpdatingLocation()
            motionManager.stopDeviceMotionUpdates()
            location = nil
            motion = nil
            refresh()
        @unknown default:
            onUpdate?(MoonFinderState(status: .locationDenied))
        }
    }

    private var supportsGuidance: Bool {
        motionManager.isDeviceMotionAvailable && CLLocationManager.headingAvailable()
            && CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
    }

    private func startMotionIfNeeded() {
        guard supportsGuidance, !motionManager.isDeviceMotionActive, !motionFailed else { return }
        // This fuses gyroscope, accelerometer and magnetometer, correcting magnetic
        // north to true north. Never substitute magnetic north for lunar azimuth.
        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, error in
            guard let self, self.isActive else { return }
            self.motionFailed = error != nil
            self.motion = motion
            self.motionReceivedAt = motion == nil ? nil : Date()
            self.refresh()
        }
    }

    static func isUsable(_ location: CLLocation, now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 10_000
            && abs(location.timestamp.timeIntervalSince(now)) <= 60
    }

    private func refresh() {
        guard isActive else { return }
        let authorization = locationManager.authorizationStatus
        guard authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            onUpdate?(MoonFinderState(status: authorization == .notDetermined ? .locating : .locationDenied))
            return
        }
        let now = Date()
        guard let location, Self.isUsable(location, now: now) else {
            onUpdate?(MoonFinderState(status: locationFailed ? .locationUnavailable : .locating))
            return
        }
        if calculatedAt == nil || now.timeIntervalSince(calculatedAt!) >= 1 {
            cachedPosition = Moon.position(at: now, latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevation: location.verticalAccuracy > 0 && location.ellipsoidalAltitude.isFinite ? location.ellipsoidalAltitude : 0,
                refraction: true)
            calculatedAt = now
        }
        guard let position = cachedPosition else {
            motionManager.stopDeviceMotionUpdates()
            motion = nil
            motionReceivedAt = nil
            onUpdate?(MoonFinderState(status: .ephemerisUnavailable))
            return
        }
        if position.altitude < 0 {
            motionManager.stopDeviceMotionUpdates()
            motion = nil
            motionReceivedAt = nil
            onUpdate?(MoonFinderState(status: .belowHorizon, position: position))
            return
        }
        guard supportsGuidance, !motionFailed else {
            onUpdate?(MoonFinderState(status: .sensorsUnavailable, position: position))
            return
        }
        startMotionIfNeeded()
        guard let motion, let receivedAt = motionReceivedAt, now.timeIntervalSince(receivedAt) < 2,
              motion.magneticField.accuracy == .medium || motion.magneticField.accuracy == .high else {
            onUpdate?(MoonFinderState(status: .calibrating, position: position))
            return
        }
        let guidance = MoonGuidance.calculate(position: position, attitude: motion.attitude.rotationMatrix)
        onUpdate?(MoonFinderState(status: .tracking, position: position, guidance: guidance))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, let latest = locations.last(where: { Self.isUsable($0, now: Date()) }) else { return }
        location = latest
        locationFailed = false
        calculatedAt = nil
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isActive else { return }
        locationFailed = true
        location = nil
        refresh()
    }
}
