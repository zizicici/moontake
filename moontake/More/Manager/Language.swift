//
//  Language.swift
//  lemon
//
//  Created by Ci Zi on 2023/7/20.
//

import Foundation

struct Language {
    enum LanguageType {
        case zh
        case en
        case ja
    }
    
    static func type() -> LanguageType {
        switch "🍋Language".localized() {
        case "简体中文", "繁体中文", "繁体中文（香港）":
            return .zh
        case "日本語":
            return .ja
        default:
            return .en
        }
    }
}
