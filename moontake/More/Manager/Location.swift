//
//  Location.swift
//  moontake
//
//  Created by Ci Zi on 2023/10/20.
//

import Foundation
import UIKit
import CoreLocation

class Location: NSObject {
    static let shared = Location()
    
    private var locationManager = CLLocationManager()
    
    override init() {
        super.init()
        
        locationManager.delegate = self
    }
    
    func requestPermission() {
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
}

extension Location: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        //
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        NotificationCenter.default.post(name: NSNotification.Name.LocationAuthorizationDidChanged, object: nil)
    }
}

extension CLAuthorizationStatus: Hashable {
    
}
