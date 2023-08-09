//
//  User.swift
//  lemon
//
//  Created by Ci Zi on 2023/7/18.
//

import Foundation

public enum ProTier {
    case lifetime
    case none
}

class User {
    static let shared = User()
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(lifetimeMembershipDidRegisted), name: NSNotification.Name.LifetimeMemberShip, object: nil)
    }
    
    @objc
    private func lifetimeMembershipDidRegisted() {
        UserDefaults.standard.setValue(true, forKey: UserDefaults.Custom.LifetimeMemberShip.rawValue)
    }
    
    func proTier() -> ProTier {
        let userDefaultLifetimeMembership = UserDefaults.standard.bool(forKey: UserDefaults.Custom.LifetimeMemberShip.rawValue)
        if userDefaultLifetimeMembership {
            return .lifetime
        } else {
            return Store.shared.proTier()
        }
    }
}
