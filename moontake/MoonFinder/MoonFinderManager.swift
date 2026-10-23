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
    var usesMagneticNorth = false
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
    private var motionReferenceFrame: CMAttitudeReferenceFrame?
    private var failedReferenceFrames: CMAttitudeReferenceFrame = []
    private var motionRetryAfter: Date?
    private var motionGeneration = 0
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
        failedReferenceFrames = []
        motionRetryAfter = nil
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
        stopMotion()
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
            stopMotion()
            location = nil
            motion = nil
            refresh()
        @unknown default:
            onUpdate?(MoonFinderState(status: .locationDenied))
        }
    }

    static func preferredReferenceFrame(available: CMAttitudeReferenceFrame,
                                        failed: CMAttitudeReferenceFrame) -> CMAttitudeReferenceFrame? {
        [.xTrueNorthZVertical, .xMagneticNorthZVertical].first {
            available.contains($0) && !failed.contains($0)
        }
    }

    private func stopMotion() {
        motionGeneration += 1
        motionManager.stopDeviceMotionUpdates()
        motionReferenceFrame = nil
        motion = nil
        motionReceivedAt = nil
    }

    private func startMotionIfNeeded(now: Date) -> Bool {
        guard motionManager.isDeviceMotionAvailable else { return false }
        if let retryAfter = motionRetryAfter {
            guard now >= retryAfter else { return false }
            failedReferenceFrames = []
            motionRetryAfter = nil
        }
        guard let referenceFrame = Self.preferredReferenceFrame(
            available: CMMotionManager.availableAttitudeReferenceFrames(), failed: failedReferenceFrames) else {
            return false
        }
        if motionManager.isDeviceMotionActive, motionReferenceFrame == referenceFrame { return true }
        stopMotion()
        motionReferenceFrame = referenceFrame
        let generation = motionGeneration
        // Some devices advertise true north but reject it at startup. Magnetic
        // north remains usable for an explicitly approximate, non-projected cue.
        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: .main) { [weak self] motion, error in
            guard let self, self.isActive, self.motionGeneration == generation else { return }
            if let error = error as NSError?,
               !(error.domain == CMErrorDomain && error.code == Int(CMErrorDeviceRequiresMovement.rawValue)) {
                self.failedReferenceFrames.insert(referenceFrame)
                self.stopMotion()
                if Self.preferredReferenceFrame(available: CMMotionManager.availableAttitudeReferenceFrames(),
                                                failed: self.failedReferenceFrames) == nil {
                    self.motionRetryAfter = Date().addingTimeInterval(5)
                }
                self.refresh()
                return
            }
            self.motion = motion
            self.motionReceivedAt = motion == nil ? nil : Date()
            self.refresh()
        }
        return true
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
            stopMotion()
            onUpdate?(MoonFinderState(status: .ephemerisUnavailable))
            return
        }
        if position.altitude < 0 {
            stopMotion()
            onUpdate?(MoonFinderState(status: .belowHorizon, position: position))
            return
        }
        guard startMotionIfNeeded(now: now) else {
            onUpdate?(MoonFinderState(status: .sensorsUnavailable, position: position))
            return
        }
        guard let motion, let receivedAt = motionReceivedAt, now.timeIntervalSince(receivedAt) < 2,
              motion.magneticField.accuracy == .medium || motion.magneticField.accuracy == .high else {
            onUpdate?(MoonFinderState(status: .calibrating, position: position))
            return
        }
        let guidance = MoonGuidance.calculate(position: position, attitude: motion.attitude.rotationMatrix)
        onUpdate?(MoonFinderState(status: .tracking, position: position, guidance: guidance,
                                 usesMagneticNorth: motionReferenceFrame == .xMagneticNorthZVertical))
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
