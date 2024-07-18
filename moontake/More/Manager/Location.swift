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
        
        locationManager.delegate = self
    }
    
    func requestAuthorization() {
        switch authorizationStatus() {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func authorizationStatus() -> CLAuthorizationStatus {
        return locationManager.authorizationStatus
    }
    
    var location: CLLocation? {
        return locationManager.location
    }
    
    func manual(disable: Bool) {
        manualDisable = disable
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
