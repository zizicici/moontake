//
//  String+Extension.swift
//  coco
//
//  Created by Ci Zi on 2023/4/20.
//

import Foundation

extension String {
    var isBlank: Bool {
        return allSatisfy({ $0.isWhitespace })
    }
}

extension Optional where Wrapped == String {
    var isBlank: Bool {
        return self?.isBlank ?? true
    }
}

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "\(self)_comment")
    }

    func localized(_ args: [CVarArg]) -> String {
        return String(format: localized, args)
    }

    func localized(_ args: CVarArg...) -> String {
        return String(format: localized, args)
    }
}
