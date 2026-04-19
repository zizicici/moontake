//
//  MorePage.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/27.
//

import UIKit
import MoreKit

func makeMorePageViewController() -> MoreViewController {
    let dataSource = MorePageDataSource()
    let controller = MoreViewController(
        configuration: MorePageFactory.makeConfiguration(),
        dataSource: dataSource
    )

    dataSource.controller = controller
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
        title: String(localized: "tutorials.title"),
        style: .plain,
        target: dataSource,
        action: #selector(MorePageDataSource.showTutorials)
    )
    controller.navigationItem.leftBarButtonItem?.tintColor = .label

    controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
        title: String(localized: "more.share"),
        style: .plain,
        target: dataSource,
        action: #selector(MorePageDataSource.shareApp)
    )
    controller.navigationItem.rightBarButtonItem?.tintColor = .label

    return controller
}

private enum MorePageFactory {
    static let supportEmail = "moon@zi.ci"
    static let appStoreID = "6451189717"
    static let privacyPolicyURL = "https://zizicici.medium.com/policy-of-privacy-for-moontake-afc746183ab7"

    static func makeConfiguration() -> MoreViewControllerConfiguration {
        MoreViewControllerConfiguration(
            title: String(localized: "More"),
            promotionConfig: PromotionCellConfiguration(
                title: String(localized: "promotion.title"),
                titleHighlight: "Pro",
                features: [
                    String(localized: "promotion.first"),
                    String(localized: "promotion.second"),
                    String(localized: "promotion.future"),
                ],
                gradientColors: [.skyColor.withAlphaComponent(0.85), .skyColor],
                titleColor: .white,
                titleHighlightColor: .systemYellow,
                featureColor: .white.withAlphaComponent(0.8),
                buttonTintColor: .systemYellow,
                buttonTextColor: .skyColor.withAlphaComponent(0.9)
            ),
            gratefulConfig: GratefulCellConfiguration(
                title: String(localized: "grateful.title"),
                titleHighlight: "Pro",
                content: String(localized: "grateful.content"),
                gradientColors: [.skyColor.withAlphaComponent(0.85), .skyColor],
                titleColor: .white,
                titleHighlightColor: .systemYellow,
                contentColor: .white.withAlphaComponent(0.8)
            ),
            email: supportEmail,
            appStoreId: appStoreID,
            privacyPolicyURL: privacyPolicyURL,
            specificationsConfig: makeSpecificationsConfiguration(),
            appShowcase: AppShowcaseConfiguration(
                apps: [.lemon, .coconut, .festivals, .pigeon, .one, .offDay, .tagDay, .pin, .campfire, .watermelon, .doufu],
                displayCount: 4,
                automaticallyIncludesFestivalsForChineseLocales: false
            )
        )
    }

    static func makeSpecificationsConfiguration() -> SpecificationsConfiguration {
        SpecificationsConfiguration(
            summaryItems: [
                .init(type: .name, value: "moontake"),
                .init(type: .version, value: SpecificationsViewController.getAppVersion() ?? ""),
                .init(type: .manufacturer, value: "@App君"),
                .init(type: .publisher, value: "ZIZICICI LIMITED"),
                .init(type: .dateOfProduction, value: "2025/09/30"),
                .init(type: .license, value: "闽ICP备2023015823号-1A"),
            ],
            thirdPartyLibraries: [
                .init(name: "astro", version: "master", urlString: "https://github.com/Starainrt/astro"),
                .init(name: "GRDB.swift", version: "6.29.3", urlString: "https://github.com/groue/GRDB.swift"),
                .init(name: "Kingfisher", version: "7.12.0", urlString: "https://github.com/onevcat/Kingfisher"),
                .init(name: "MoreKit", version: "1.6.1", urlString: "https://github.com/zizicici/MoreKit"),
                .init(name: "SnapKit", version: "5.7.1", urlString: "https://github.com/SnapKit/SnapKit"),
                .init(name: "Toast", version: "5.1.1", urlString: "https://github.com/scalessec/Toast-Swift"),
            ],
            title: String(localized: "Specifications")
        )
    }
}

private final class MorePageDataSource: NSObject, MoreViewControllerDataSource {
    private enum SectionID: String {
        case settings
    }

    private enum ItemID: String {
        case language
        case iso
        case whiteBalance
        case saveOptions
    }

    weak var controller: MoreViewController?

    func sections(for controller: MoreViewController) -> [MoreSectionType] {
        [
            .membership,
            .custom(settingsSection()),
            .contact,
            .appjun,
            .about,
        ]
    }

    func moreViewController(_ controller: MoreViewController, didSelectCustomItem item: MoreCustomItem) {
        guard let itemID = ItemID(rawValue: item.id) else {
            return
        }

        switch itemID {
        case .language:
            controller.jumpToSettings()
        case .iso:
            controller.enterSettings(Settings.ISOOption.self)
        case .whiteBalance:
            controller.enterSettings(Settings.WhiteBalanceOption.self)
        case .saveOptions:
            controller.enterSettings(Settings.SaveToAlbumOption.self)
        }
    }

    func additionalReloadNotifications() -> [Notification.Name] {
        [.ISOUpdated, .WhiteBalanceUpdated]
    }

    @objc
    func showTutorials() {
        guard let controller else {
            return
        }

        let tutorialsVC = TutorialsViewController()
        let nav = UINavigationController(rootViewController: tutorialsVC)
        controller.navigationController?.present(nav, animated: true)
    }

    @objc
    func shareApp() {
        guard let controller,
              let url = URL(string: "https://apps.apple.com/app/id\(MorePageFactory.appStoreID)") else {
            return
        }

        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.present(activityController, animated: true)
    }

    private func settingsSection() -> MoreCustomSection {
        MoreCustomSection(
            id: SectionID.settings.rawValue,
            header: String(localized: "Settings"),
            items: [
                MoreCustomItem(
                    id: ItemID.language.rawValue,
                    title: String(localized: "Language"),
                    value: String(localized: "🍋Language")
                ),
                MoreCustomItem(
                    id: ItemID.iso.rawValue,
                    title: String(localized: "ISO"),
                    value: Settings.shared.getISOSettings().title
                ),
                MoreCustomItem(
                    id: ItemID.whiteBalance.rawValue,
                    title: String(localized: "White Balance Temperature"),
                    value: Settings.shared.getWhiteBalanceSettings().title
                ),
                MoreCustomItem(
                    id: ItemID.saveOptions.rawValue,
                    title: String(localized: "Photo Save Options"),
                    value: Settings.shared.getSaveToAlbumSettings().title
                ),
            ]
        )
    }
}
