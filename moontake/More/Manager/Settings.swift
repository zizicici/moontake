//
//  Settings.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import Foundation
import MoreKit

struct Settings {
    static let shared = Settings()
    
    enum SaveToAlbumOption: Int, Hashable {
        case photoWithWatermark = 0
        case photoWithoutWatermark = 1
        case both = 2
        
        var title: String {
            switch self {
            case .photoWithWatermark:
                return String(localized: "photo.watermarked.title")
            case .photoWithoutWatermark:
                return String(localized: "photo.original.title")
            case .both:
                return String(localized: "photo.original.title") + " + " + String(localized: "photo.watermarked.title")
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

private enum SettingsSelectionError: LocalizedError {
    case proRequired

    var errorDescription: String? {
        switch self {
        case .proRequired:
            return String(localized: "This option is only for Pro user.")
        }
    }
}

extension Settings.SaveToAlbumOption: SettingsOption {
    func getName() -> String {
        title
    }

    static func getTitle() -> String {
        String(localized: "Photo Save Options")
    }

    static func getHeader() -> String? {
        String(localized: "settings.save.photoLibrary")
    }

    static func getFooter() -> String? {
        if User.shared.proTier() == .lifetime {
            return nil
        } else {
            return String(localized: "For free users, the default option is automatically selected and not customizable.")
        }
    }

    static func getOptions() -> [Self] {
        [.photoWithoutWatermark, .photoWithWatermark, .both]
    }

    static var current: Self {
        Settings.shared.getSaveToAlbumSettings()
    }

    static func setCurrent(_ value: Self) throws {
        guard Settings.shared.save(option: value) else {
            throw SettingsSelectionError.proRequired
        }
        NotificationCenter.default.post(name: .SettingsUpdate, object: nil)
    }
}

extension Settings.ISOOption: SettingsOption {
    func getName() -> String {
        title
    }

    static func getTitle() -> String {
        String(localized: "ISO Options")
    }

    static func getFooter() -> String? {
        String(localized: "In theory, under the same exposure time, a lower ISO value tends to reduce image noise.\nHowever, a lower ISO value may result in longer exposure time, which often requires a more stable camera support to avoid potential blurriness in the image.")
    }

    static func getOptions() -> [Self] {
        [.default] + Camera.shared.getISOCandidates().map { .value($0) }
    }

    static var current: Self {
        Settings.shared.getISOSettings()
    }

    static func setCurrent(_ value: Self) throws {
        Settings.shared.save(option: value)
        NotificationCenter.default.post(name: .SettingsUpdate, object: nil)
    }
}

extension Settings.WhiteBalanceOption: SettingsOption {
    func getName() -> String {
        title
    }

    static func getTitle() -> String {
        String(localized: "White Balance Temperature")
    }

    static func getOptions() -> [Self] {
        [.default] + Camera.shared.getWhiteBalanceCandidates().map { .value($0) }
    }

    static var current: Self {
        Settings.shared.getWhiteBalanceSettings()
    }

    static func setCurrent(_ value: Self) throws {
        Settings.shared.save(option: value)
        NotificationCenter.default.post(name: .SettingsUpdate, object: nil)
    }
}
