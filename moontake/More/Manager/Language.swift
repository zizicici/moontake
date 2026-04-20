//
//  Language.swift
//  lemon
//
//  Created by Ci Zi on 2023/7/20.
//

import Foundation

struct Language {
    enum LanguageType {
        case de
        case en
        case es
        case es419
        case fr
        case ja
        case ptBR
        case ptPT
        case ru
        case uk
        case zhHans
        case zhHant
        case zhHK

        var displayName: String {
            switch self {
            case .de:
                "Deutsch"
            case .en:
                "English"
            case .es:
                "Español"
            case .es419:
                "Español (Latinoamérica)"
            case .fr:
                "Français"
            case .ja:
                "日本語"
            case .ptBR:
                "Português (Brasil)"
            case .ptPT:
                "Português (Portugal)"
            case .ru:
                "Русский"
            case .uk:
                "Українська"
            case .zhHans:
                "简体中文"
            case .zhHant:
                "繁體中文"
            case .zhHK:
                "繁體中文（香港）"
            }
        }
    }

    static func current() -> LanguageType {
        let preferredIdentifier = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return resolve(identifier: preferredIdentifier)
    }

    static func type() -> LanguageType {
        current()
    }

    private static func resolve(identifier: String) -> LanguageType {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")

        switch normalized {
        case "de":
            return .de
        case "en":
            return .en
        case "es":
            return .es
        case "es-419":
            return .es419
        case "fr":
            return .fr
        case "ja":
            return .ja
        case "pt-BR":
            return .ptBR
        case "pt-PT":
            return .ptPT
        case "ru":
            return .ru
        case "uk":
            return .uk
        case "zh-Hans", "zh-CN", "zh-SG":
            return .zhHans
        case "zh-Hant", "zh-TW":
            return .zhHant
        case "zh-HK", "zh-MO":
            return .zhHK
        default:
            break
        }

        switch normalized.split(separator: "-").first {
        case "de":
            return .de
        case "en":
            return .en
        case "es":
            return .es
        case "fr":
            return .fr
        case "ja":
            return .ja
        case "pt":
            return .ptBR
        case "ru":
            return .ru
        case "uk":
            return .uk
        case "zh":
            return .zhHans
        default:
            return .en
        }
    }
}
