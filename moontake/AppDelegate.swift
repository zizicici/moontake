//
//  AppDelegate.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//

import UIKit
import ZCCalendar

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        _ = AppDatabase.shared
        _ = User.shared
        _ = Store.shared
        
        DispatchQueue.global(qos: .background).async {
            let today = ZCCalendar.manager.today
            switch today.month {
            case .jan:
                if today.day == 1 {
                    MoonManager.shared.loadData(year: today.year - 1, to: today.year)
                } else {
                    MoonManager.shared.loadData(year: today.year, to: today.year)
                }
            case .dec:
                if today.day == 31 {
                    MoonManager.shared.loadData(year: today.year, to: today.year + 1)
                } else {
                    MoonManager.shared.loadData(year: today.year, to: today.year)
                }
            default:
                MoonManager.shared.loadData(year: today.year, to: today.year)
            }
        }
        
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

