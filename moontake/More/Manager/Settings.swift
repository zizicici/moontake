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
                return "Photo with Watermark".localized()
            case .photoWithoutWatermark:
                return "Photo without Watermark".localized()
            case .both:
                return "Both above".localized()
            }
        }
    }
    
    enum WatermarkTypeOption: Int, Hashable {
        case qrCode = 0
        case icon = 1
        case location = 2
        case blank = 10
        
        var title: String {
            switch self {
            case .qrCode:
                return "QR Code".localized()
            case .icon:
                return "App Icon".localized()
            case .location:
                return "Location".localized()
            case .blank:
                return "None".localized()
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
    
    func getWatermarkTypeSettings() -> WatermarkTypeOption {
        let rawValue = UserDefaults.standard.getInt(forKey: UserDefaults.Custom.WatermarkType.rawValue)
        return WatermarkTypeOption(rawValue: rawValue ?? 0) ?? .qrCode
    }
    
    func save(option: WatermarkTypeOption) -> Bool {
        var allowSave: Bool = false
        if User.shared.proTier() == .none {
            switch option {
            case .qrCode:
                allowSave = true
            case .blank:
                allowSave = true
            case .location:
                allowSave = false
            case .icon:
                allowSave = false
            }
        } else {
            allowSave = true
        }
        if allowSave {
            UserDefaults.standard.setValue(option.rawValue, forKey: UserDefaults.Custom.WatermarkType.rawValue)
        }
        return allowSave
    }
}
