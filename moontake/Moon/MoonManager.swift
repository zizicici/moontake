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
            if getPhasePercent() > 0.9975 {
                currentPhase = .fullMoon
            } else {
                currentPhase = .waxingMoon
            }
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
    
    func getPhaseName() -> String {
        switch getPhase() {
        case .newMoon:
            return "New Moon".localized()
        case .waxingMoon:
            let percent = getPhasePercent()
            if percent < 0.49 {
                // 娥眉月
                return "WaxingMoon1".localized()
            } else if percent < 0.51 {
                // 上弦月
                return "WaxingMoon2".localized()
            } else {
                // 上凸月
                return "WaxingMoon3".localized()
            }
        case .fullMoon:
            return "Full Moon".localized()
        case .waningMoon:
            let percent = getPhasePercent()
            if percent < 0.49 {
                // 残月
                return "WaningMoon1".localized()
            } else if percent < 0.51 {
                // 下弦月
                return "WaningMoon2".localized()
            } else {
                // 下凸月
                return "WaningMoon3".localized()
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
