//
//  AppDelegate.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//

import UIKit
import Kingfisher
import MoreKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        _ = AppDatabase.shared
        MoreKit.configure(
            productID: "com.zizicici.moontake.iap.lifetime",
            membershipKey: UserDefaults.Custom.LifetimeMemberShip.rawValue
        )
        MoreKitAppearance.shared = MoreKitAppearance(
            backgroundColor: .backgroundColor,
            tintColor: .label
        )
        KingfisherManager.shared.cache.memoryStorage.config.totalCostLimit = 150 * 1024 * 1024
        KingfisherManager.shared.cache.diskStorage.config.sizeLimit = 50 * 1024 * 1024
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}
