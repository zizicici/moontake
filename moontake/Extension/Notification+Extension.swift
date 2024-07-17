//
//  Notification+Extension.swift
//  coco
//
//  Created by Ci Zi on 2023/5/11.
//

import Foundation

extension Notification.Name {
    static let ISOUpdated = Notification.Name(rawValue: "com.zizicici.moontake.ISOUpate")
    static let WhiteBalanceUpdated = Notification.Name(rawValue: "com.zizicici.moontake.WhiteBalanceUpate")
    static let LocationAuthorizationDidChanged = Notification.Name(rawValue: "com.zizicici.moontake.LocationAuthorizationDidChanged")
}
