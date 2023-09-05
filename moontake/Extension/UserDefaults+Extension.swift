//
//  UserDefaults+Extension.swift
//  coco
//
//  Created by Ci Zi on 2023/4/28.
//

import Foundation

extension UserDefaults {
    enum Custom: String {
        case LifetimeMemberShip = "com.zizicici.moontake.store.purchase.lifetime"
        case SaveToAlbum = "com.zizicici.moontake.settings.saveToAlbum"
        case WatermarkType = "com.zizicici.moontake.settings.watermarkType"
        case ISO = "com.zizicici.moontake.settings.iso"
    }
}

extension UserDefaults {
    func getInt(forKey key: String) -> Int? {
        if value(forKey: key) == nil {
            return nil
        } else {
            return integer(forKey: key)
        }
    }
    
    func getFloat(forKey key: String) -> Float? {
        if value(forKey: key) == nil {
            return nil
        } else {
            return float(forKey: key)
        }
    }
    
    func getString(forKey key: String) -> String? {
        if value(forKey: key) == nil {
            return nil
        } else {
            return string(forKey: key)
        }
    }
}
