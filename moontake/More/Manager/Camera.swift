//
//  Camera.swift
//  moontake
//
//  Created by Ci Zi on 2023/9/5.
//

import Foundation

class Camera {
    static let shared = Camera()
    
    var minISO: Float = 50.0
    var maxISO: Float = 1000.0
    
    func update(minISO: Float, maxISO: Float) {
        self.minISO = minISO
        self.maxISO = maxISO
//        print("最小ISO值: \(minISO)")
//        print("最大ISO值: \(maxISO)")
    }
    
    func getISOCandidates() -> [Float] {
        let array: [Float] = [50.0, 100.0, 150.0, 200.0]
        
        var result = [minISO]
        
        result.append(contentsOf: array.filter{ $0 > minISO })
        
        return result
    }
    
    func preferredValue() -> Float {
        return max(minISO, 50.0)
    }
    
    func getWhiteBalanceCandidates() -> [Float] {
        return [3000.0, 3500.0, 4000.0, 4500.0, 5000.0, 5500.0, 6000.0, 6500.0, 7000.0, 7500.0]
    }
    
    func preferredWhiteBalanceValue() -> Float {
        return 5500.0
    }
}
