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

    enum AppAlbumOption: Int, Hashable {
        case enable = 0
        case disable = 1

        var title: String {
            switch self {
            case .enable:
                return String(localized: "settings.app_album.enable")
            case .disable:
                return String(localized: "settings.app_album.disable")
            }
        }
    }
    
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
                return String.localizedStringWithFormat(
                    String(localized: "settings.save.both"),
                    String(localized: "photo.original.title"),
                    String(localized: "photo.watermarked.title")
                )
            }
        }
    }
    
    enum ISOOption: Hashable {
        case `default`
        case value(Float)
        
        var title: String {
            switch self {
            case .default:
                return String.localizedStringWithFormat(
                    String(localized: "settings.iso.default"),
                    String(localized: "settings.default"),
                    Camera.shared.preferredValue()
                )
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
                return String.localizedStringWithFormat(
                    String(localized: "settings.white_balance.default"),
                    String(localized: "settings.default"),
                    Camera.shared.preferredWhiteBalanceValue()
                )
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
    
    func getAppAlbumSettings() -> AppAlbumOption {
        let rawValue = UserDefaults.standard.getInt(forKey: UserDefaults.Custom.AppAlbum.rawValue)
        return AppAlbumOption(rawValue: rawValue ?? 0) ?? .enable
    }

    @discardableResult
    func save(option: AppAlbumOption) -> Bool {
        let allowSave: Bool
        if User.shared.proTier() == .none {
            switch option {
            case .enable:
                allowSave = true
            case .disable:
                allowSave = false
            }
        } else {
            allowSave = true
        }

        if allowSave {
            UserDefaults.standard.setValue(option.rawValue, forKey: UserDefaults.Custom.AppAlbum.rawValue)
        }
        return allowSave
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
            return String(localized: "settings.pro_required.error")
        }
    }
}

extension Settings.AppAlbumOption: SettingsOption {
    func getName() -> String {
        title
    }

    static func getTitle() -> String {
        String(localized: "settings.app_album.title")
    }

    static func getFooter() -> String? {
        let baseFooter = String(localized: "settings.app_album.footer")
        guard User.shared.proTier() != .lifetime else {
            return baseFooter
        }

        let proFooter = String(localized: "settings.app_album.pro_footer")
        return baseFooter + "\n\n" + proFooter
    }

    static func getOptions() -> [Self] {
        [.enable, .disable]
    }

    static var current: Self {
        Settings.shared.getAppAlbumSettings()
    }

    static func setCurrent(_ value: Self) throws {
        guard Settings.shared.save(option: value) else {
            throw SettingsSelectionError.proRequired
        }
        NotificationCenter.default.post(name: .SettingsUpdate, object: nil)
    }
}

extension Settings.SaveToAlbumOption: SettingsOption {
    func getName() -> String {
        title
    }

    static func getTitle() -> String {
        String(localized: "settings.save.title")
    }

    static func getFooter() -> String? {
        let baseFooter = String(localized: "settings.save.footer")
        guard User.shared.proTier() != .lifetime else {
            return baseFooter
        }

        let proFooter = String(localized: "settings.save.pro_footer")
        return baseFooter + "\n\n" + proFooter
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
        String(localized: "settings.iso.options.title")
    }

    static func getFooter() -> String? {
        String(localized: "settings.iso.footer")
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
        String(localized: "settings.white_balance.title")
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
