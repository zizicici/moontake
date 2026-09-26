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
    let tutorialsItem = UIBarButtonItem(
        title: String(localized: "tutorials.title"),
        style: .plain,
        target: dataSource,
        action: #selector(MorePageDataSource.showTutorials)
    )
    tutorialsItem.tintColor = .label

    let shareItem = UIBarButtonItem(
        title: String(localized: "more.share"),
        style: .plain,
        target: dataSource,
        action: #selector(MorePageDataSource.shareApp)
    )
    shareItem.tintColor = .label

    if Language.current().isRightToLeft {
        controller.navigationItem.rightBarButtonItem = tutorialsItem
        controller.navigationItem.leftBarButtonItem = shareItem
    } else {
        controller.navigationItem.leftBarButtonItem = tutorialsItem
        controller.navigationItem.rightBarButtonItem = shareItem
    }

    return controller
}

private enum MorePageFactory {
    static let supportEmail = "moon@zi.ci"
    static let appStoreID = "6451189717"
    static let privacyPolicyURL = "https://zizicici.medium.com/policy-of-privacy-for-moontake-afc746183ab7"

    static func makeConfiguration() -> MoreViewControllerConfiguration {
        MoreViewControllerConfiguration(
            title: String(localized: "more.title"),
            promotionConfig: PromotionCellConfiguration(
                title: String(localized: "promotion.title"),
                titleHighlight: "Pro",
                features: [
                    String(localized: "promotion.first"),
                    String(localized: "promotion.second"),
                    String(localized: "promotion.moon_calendar"),
                    String(localized: "promotion.future"),
                ],
                gradientColors: [.skyColor.withAlphaComponent(0.85), .skyColor],
                titleColor: .white,
                titleHighlightColor: .systemYellow,
                featureColor: .white.withAlphaComponent(0.8),
                buttonTintColor: .systemYellow,
                buttonTextColor: .skyColor.withAlphaComponent(0.9),
                buttonTitle: String(localized: "membership.purchase"),
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
                .init(type: .dateOfProduction, value: "2026/09/26"),
                .init(type: .license, value: "闽ICP备2023015823号-1A"),
            ],
            thirdPartyLibraries: [
                .init(name: "ERFA", version: "2.0.1", urlString: "https://github.com/liberfa/erfa"),
                .init(name: "JPL Lunar Ephemeris", version: "DE440", urlString: "https://ssd.jpl.nasa.gov/planets/eph_export.html"),
                .init(name: "GRDB.swift", version: "6.29.3", urlString: "https://github.com/groue/GRDB.swift"),
                .init(name: "Kingfisher", version: "7.12.0", urlString: "https://github.com/onevcat/Kingfisher"),
                .init(name: "MoreKit", version: "2.0.1", urlString: "https://github.com/zizicici/MoreKit"),
                .init(name: "SkyKit", version: "1.0.0", urlString: "https://github.com/zizicici/SkyKit"),
                .init(name: "SnapKit", version: "5.7.1", urlString: "https://github.com/SnapKit/SnapKit"),
                .init(name: "Toast", version: "5.1.1", urlString: "https://github.com/scalessec/Toast-Swift"),
            ],
            title: String(localized: "specifications.title")
        )
    }
}

private final class MorePageDataSource: NSObject, MoreViewControllerDataSource {
    private enum SectionID: String {
        case settings
        case photoSaving
    }

    private enum ItemID: String {
        case language
        case iso
        case whiteBalance
        case appAlbum
        case saveOptions
    }

    weak var controller: MoreViewController?

    func sections(for controller: MoreViewController) -> [MoreSectionType] {
        [
            .membership,
            .custom(settingsSection()),
            .custom(photoSavingSection()),
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
        case .appAlbum:
            controller.enterSettings(Settings.AppAlbumOption.self)
        case .saveOptions:
            controller.enterSettings(Settings.SaveToAlbumOption.self)
        }
    }

    func additionalReloadNotifications() -> [Notification.Name] {
        [.ISOUpdated, .WhiteBalanceUpdated, .SettingsUpdate]
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

    private func proBadgeStyle() -> MoreBadgeStyle? {
        guard User.shared.proTier() != .lifetime else {
            return nil
        }

        return MoreBadgeStyle(
            text: "Pro",
            textColor: .skyColor,
            backgroundColor: .systemYellow
        )
    }

    private func settingsSection() -> MoreCustomSection {
        MoreCustomSection(
            id: SectionID.settings.rawValue,
            header: String(localized: "settings.title"),
            items: [
                MoreCustomItem(
                    id: ItemID.language.rawValue,
                    title: String(localized: "settings.language.title"),
                    value: Language.current().displayName
                ),
                MoreCustomItem(
                    id: ItemID.iso.rawValue,
                    title: String(localized: "settings.iso.label"),
                    value: Settings.shared.getISOSettings().title
                ),
                MoreCustomItem(
                    id: ItemID.whiteBalance.rawValue,
                    title: String(localized: "settings.white_balance.title"),
                    value: Settings.shared.getWhiteBalanceSettings().title
                ),
            ]
        )
    }

    private func photoSavingSection() -> MoreCustomSection {
        MoreCustomSection(
            id: SectionID.photoSaving.rawValue,
            header: String(localized: "settings.photo_saving.title"),
            items: [
                MoreCustomItem(
                    id: ItemID.saveOptions.rawValue,
                    title: String(localized: "settings.save.title"),
                    value: Settings.shared.getSaveToAlbumSettings().title,
                    badge: proBadgeStyle()
                ),
                MoreCustomItem(
                    id: ItemID.appAlbum.rawValue,
                    title: String(localized: "settings.app_album.title"),
                    value: Settings.shared.getAppAlbumSettings().title,
                    badge: proBadgeStyle()
                ),
            ]
        )
    }
}
