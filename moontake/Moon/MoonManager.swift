//
//  MoonManager.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/4.
//

import Foundation
import Mooninfo

struct MoonManager {
    static let shared = MoonManager()
    
    enum Phase {
        case newMoon
        case waxingMoon
        case fullMoon
        case waningMoon
    }
    
    func getPhasePercent() -> Double {
        return MooninfoAt(Int64(Date().timeIntervalSince1970))
    }
    
    func getPhase() -> Phase {
        let timestamp = Int64(Date().timeIntervalSince1970)
        let nextNewMoon = MooninfoNextNewMoon(timestamp)
        let nextWaxingMoon = MooninfoNextWaxingMoon(timestamp)
        let nextFullMoon = MooninfoNextFullMoon(timestamp)
        let nextWaningMoon = MooninfoNextWaningMoon(timestamp)
        
        let minValue = min(min(nextNewMoon, nextWaxingMoon), min(nextFullMoon, nextWaningMoon))
        
        let currentPhase: Phase!
        switch minValue {
        case nextNewMoon:
            currentPhase = .waningMoon
        case nextWaxingMoon:
            if getPhasePercent() < 0.025 {
                currentPhase = .newMoon
            } else {
                currentPhase = .waxingMoon
            }
        case nextFullMoon:
            currentPhase = .waxingMoon
        case nextWaningMoon:
            if getPhasePercent() > 0.975 {
                currentPhase = .fullMoon
            } else {
                currentPhase = .waningMoon
            }
        default:
            currentPhase = .newMoon
        }
        
        return currentPhase
    }
}
