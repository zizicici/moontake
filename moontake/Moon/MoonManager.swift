//
//  MoonManager.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/4.
//

import Foundation
import Mooninfo

class MoonManager {
    static let shared = MoonManager()
    
    var fullMoonDates: [TimeInterval] = []
    
    var newMoonDates: [TimeInterval] = []
    
    var isLoading: Bool = false
    
    enum Phase {
        case newMoon
        case waxingMoon
        case fullMoon
        case waningMoon
    }
    
    func getPhasePercent(_ date: Date) -> Double {
        var phasePercent = MooninfoAt(Int64(date.timeIntervalSince1970))
        let currentDate = date.timeIntervalSince1970
        if phasePercent > 0.975 {
            if let result = MoonManager.shared.findClosestFullMoon(target: currentDate) {
                if abs(currentDate - result) < 60 * 60 * 2 {
                    phasePercent = 1.0
                }
            } else {
                if phasePercent > 0.9975 {
                    phasePercent = 1.0
                }
            }
        } else if phasePercent < 0.025 {
            if let result = MoonManager.shared.findClosestNewMoon(target: currentDate) {
                if abs(currentDate - result) < 60 * 60 * 2 {
                    phasePercent = 0.0
                }
            } else {
                if phasePercent < 0.005 {
                    phasePercent = 0.0
                }
            }
        }
        return phasePercent
    }
    
    func getPhase(_ date: Date) -> Phase {
        let timestamp = Int64(date.timeIntervalSince1970)
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
            if getPhasePercent(date) < 0.025 {
                currentPhase = .newMoon
            } else {
                currentPhase = .waxingMoon
            }
        case nextFullMoon:
            if getPhasePercent(date) > 0.9975 {
                currentPhase = .fullMoon
            } else {
                currentPhase = .waxingMoon
            }
        case nextWaningMoon:
            if getPhasePercent(date) > 0.975 {
                currentPhase = .fullMoon
            } else {
                currentPhase = .waningMoon
            }
        default:
            currentPhase = .newMoon
        }
        
        return currentPhase
    }
    
    func getPhaseName(_ date: Date) -> String {
        switch getPhase(date) {
        case .newMoon:
            return String(localized: "New Moon")
        case .waxingMoon:
            let percent = getPhasePercent(date)
            if percent < 0.49 {
                // 娥眉月
                return String(localized: "WaxingMoon1")
            } else if percent < 0.51 {
                // 上弦月
                return String(localized: "WaxingMoon2")
            } else {
                // 上凸月
                return String(localized: "WaxingMoon3")
            }
        case .fullMoon:
            return String(localized: "Full Moon")
        case .waningMoon:
            let percent = getPhasePercent(date)
            if percent < 0.49 {
                // 残月
                return String(localized: "WaningMoon1")
            } else if percent < 0.51 {
                // 下弦月
                return String(localized: "WaningMoon2")
            } else {
                // 下凸月
                return String(localized: "WaningMoon3")
            }
        }
    }
    
    func loadData(year from: Int, to: Int) {
        isLoading = true
        fullMoonDates = []
        newMoonDates = []
        for year in Array(from...to) {
            let result = AstronomyManager.shared.calculate(year: year)
            for element in result {
                switch element.state {
                case .fullMoon:
                    fullMoonDates.append(element.date.timeIntervalSince1970)
                case .newMoon:
                    newMoonDates.append(element.date.timeIntervalSince1970)
                default:
                    break
                }
            }
        }
        isLoading = false
    }
    
    func findClosestFullMoon(target: TimeInterval) -> TimeInterval? {
        guard !isLoading else {
            return nil
        }
        return findClosestValue(target, in: fullMoonDates)
    }
    
    func findClosestNewMoon(target: TimeInterval) -> TimeInterval? {
        guard !isLoading else {
            return nil
        }
        return findClosestValue(target, in: newMoonDates)
    }
    
    func findClosestValue(_ target: TimeInterval, in array: [TimeInterval]) -> TimeInterval? {
        guard !array.isEmpty else {
            return nil // 如果数组为空，则返回nil
        }
        
        var closestValue = array[0] // 假设第一个元素为初始最接近的值
        
        for value in array {
            if abs(target - value) < abs(target - closestValue) {
                closestValue = value // 更新最接近的值
            }
        }
        
        return closestValue
    }
}
