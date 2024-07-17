//
//  Settings.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import Foundation

struct Settings {
    static let shared = Settings()
    
    enum SaveToAlbumOption: Int, Hashable {
        case photoWithWatermark = 0
        case photoWithoutWatermark = 1
        case both = 2
        
        var title: String {
            switch self {
            case .photoWithWatermark:
                return String(localized: "Photo with Watermark")
            case .photoWithoutWatermark:
                return String(localized: "Photo without Watermark")
            case .both:
                return String(localized: "Both above")
            }
        }
    }
    
    enum ISOOption: Hashable {
        case `default`
        case value(Float)
        
        var title: String {
            switch self {
            case .default:
                return String(localized: "Default") + String(format: " [%.0f]", Camera.shared.preferredValue())
            case .value(let isoValue):
                return String(format: "%.0f", isoValue)
            }
        }
        
        var isoValue: Float {
            switch self {
            case .default:
                return Camera.shared.preferredValue()
            case .value(let storedValue):
                return storedValue
            }
        }
    }
    
    enum WhiteBalanceOption: Hashable {
        case `default`
        case value(Float)
        
        var title: String {
            switch self {
            case .default:
                return String(localized: "Default") + String(format: " [%.0fK]", Camera.shared.preferredWhiteBalanceValue())
            case .value(let tempValue):
                return String(format: "%.0fK", tempValue)
            }
        }
        
        var temperatureValue: Float {
            switch self {
            case .default:
                return Camera.shared.preferredWhiteBalanceValue()
            case .value(let storedValue):
                return storedValue
            }
        }
    }
    
    func getSaveToAlbumSettings() -> SaveToAlbumOption {
        let rawValue = UserDefaults.standard.getInt(forKey: UserDefaults.Custom.SaveToAlbum.rawValue)
        return SaveToAlbumOption(rawValue: rawValue ?? 0) ?? .photoWithWatermark
    }
    
    func save(option: SaveToAlbumOption) -> Bool {
        var allowSave: Bool = false
        if User.shared.proTier() == .none {
            switch option {
            case .photoWithWatermark:
                allowSave = true
            default:
                allowSave = false
            }
        } else {
            allowSave = true
        }
        if allowSave {
            UserDefaults.standard.setValue(option.rawValue, forKey: UserDefaults.Custom.SaveToAlbum.rawValue)
        }
        return allowSave
    }
    
    func getISOSettings() -> ISOOption {
        if let isoValue = UserDefaults.standard.getFloat(forKey: UserDefaults.Custom.ISO.rawValue) {
            return .value(isoValue)
        } else {
            return .default
        }
    }
    
    @discardableResult
    func save(option: ISOOption) -> Bool {
        switch option {
        case .default:
            UserDefaults.standard.removeObject(forKey: UserDefaults.Custom.ISO.rawValue)
        case .value(let value):
            UserDefaults.standard.setValue(value, forKey: UserDefaults.Custom.ISO.rawValue)
        }
        NotificationCenter.default.post(name: NSNotification.Name.ISOUpdated, object: nil)
        return true
    }
    
    func getWhiteBalanceSettings() -> WhiteBalanceOption {
        if let tempValue = UserDefaults.standard.getFloat(forKey: UserDefaults.Custom.WhiteBalance.rawValue) {
            return .value(tempValue)
        } else {
            return .default
        }
    }
    
    @discardableResult
    func save(option: WhiteBalanceOption) -> Bool {
        switch option {
        case .default:
            UserDefaults.standard.removeObject(forKey: UserDefaults.Custom.WhiteBalance.rawValue)
        case .value(let value):
            UserDefaults.standard.setValue(value, forKey: UserDefaults.Custom.WhiteBalance.rawValue)
        }
        NotificationCenter.default.post(name: NSNotification.Name.WhiteBalanceUpdated, object: nil)
        return true
    }
    
}
