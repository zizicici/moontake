//
//  Location.swift
//  moontake
//
//  Created by Ci Zi on 2023/10/20.
//

import Foundation
import CoreLocation

extension Notification.Name {
    static let LocationAuthorizationDidChanged = Notification.Name(rawValue: "com.zizicici.moontake.LocationAuthorizationDidChanged")
    static let LocationInformationDidChanged = Notification.Name(rawValue: "com.zizicici.moontake.LocationInformationDidChanged")
}

class Location: NSObject {
    static let shared = Location()
    
    private var locationManager = CLLocationManager()
    
    private(set) var manualDisable: Bool = false {
        didSet {
            updateLocationUpdateState()
        }
    }
    
    private var disableUpdating: Bool = false {
        didSet {
            updateLocationUpdateState()
        }
    }
    
    override init() {
        super.init()
        let key = UserDefaults.Custom.LocationMetadataDisabled.rawValue
        if let saved = UserDefaults.standard.object(forKey: key) as? Bool {
            manualDisable = saved
        } else {
            // Preserve geotagging for existing authorized users. New users opt in
            // from the photo-location menu, independently of finder permission.
            let status = locationManager.authorizationStatus
            manualDisable = status != .authorizedAlways && status != .authorizedWhenInUse
            UserDefaults.standard.set(manualDisable, forKey: key)
        }
        locationManager.delegate = self
    }
    
    func requestAuthorization() {
        switch authorizationStatus() {
        case .notDetermined:
            manual(disable: false)
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func authorizationStatus() -> CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }
    
    var location: CLLocation? {
        if manualDisable {
            return nil
        }
        return locationManager.location
    }
    
    func manual(disable: Bool) {
        manualDisable = disable
        UserDefaults.standard.set(disable, forKey: UserDefaults.Custom.LocationMetadataDisabled.rawValue)
        postNotification()
    }
    
    func updateLocationUpdateState() {
        switch authorizationStatus() {
        case .notDetermined:
            locationManager.stopUpdatingLocation()
        case .restricted, .denied:
            locationManager.stopUpdatingLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            if manualDisable || disableUpdating {
                locationManager.stopUpdatingLocation()
            } else {
                locationManager.startUpdatingLocation()
            }
        @unknown default:
            locationManager.stopUpdatingLocation()
        }
    }
    
    func resumeLocationUpdate() {
        disableUpdating = false
    }
    
    func stopLocationUpdate() {
        disableUpdating = true
    }
    
    func postNotification() {
        NotificationCenter.default.post(name: NSNotification.Name.LocationInformationDidChanged, object: nil)
    }
}

extension Location: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print(locations.first ?? "no location")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        NotificationCenter.default.post(name: NSNotification.Name.LocationAuthorizationDidChanged, object: nil)
        
        updateLocationUpdateState()
    }
}

extension CLAuthorizationStatus: Hashable {
    
}
