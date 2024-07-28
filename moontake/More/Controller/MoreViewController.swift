//
//  MoreViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/27.
//

import UIKit
import SnapKit
import SafariServices
import AppInfo
import StoreKit

class MoreViewController: UIViewController {
    static let supportEmail = "moon@zi.ci"

    private var tableView: UITableView!
    private var dataSource: DataSource!
    
    enum Section: Hashable {
        case membership
        case settings
        case tutorials
        case appjun
        case about
        
        var header: String? {
            switch self {
            case .membership:
                return " "
            case .settings:
                return String(localized: "Settings")
            case .tutorials:
                return String(localized: "tutorials.title")
            case .appjun:
                return String(localized: "App from AppJun")
            case .about:
                return String(localized: "About")
            }
        }
        
        var footer: String? {
            return nil
        }
    }
    
    enum Item: Hashable {
        enum GeneralItem {
            case language
            case iso
            case whiteBalance
            case saveOptions
            
            var title: String {
                switch self {
                case .language:
                    return String(localized: "Language")
                case .iso:
                    return String(localized: "ISO")
                case .whiteBalance:
                    return String(localized: "White Balance Temperature")
                case .saveOptions:
                    return String(localized: "Photo Save Options")
                }
            }
            
            var value: String? {
                switch self {
                case .language:
                    return String(localized: "🍋Language")
                case .iso:
                    return Settings.shared.getISOSettings().title
                case .whiteBalance:
                    return Settings.shared.getWhiteBalanceSettings().title
                default:
                    return nil
                }
            }
        }
        
        enum AboutItem {
            case specifications
            case share
            case review
            case eula
            case privacyPolicy
            case email
            
            var title: String {
                switch self {
                case .specifications:
                    return String(localized: "Specifications")
                case .share:
                    return String(localized: "Share App")
                case .review:
                    return String(localized: "Write Review")
                case .eula:
                    return String(localized: "EULA")
                case .privacyPolicy:
                    return String(localized: "Policy of Privacy")
                case .email:
                    return String(localized: "Email")
                }
            }
            
            var value: String? {
                switch self {
                case .email:
                    return MoreViewController.supportEmail
                default:
                    return nil
                }
            }
        }
        
        enum AppJunItem: Hashable {
            case otherApps(App)
            case bilibili
            case xiaohongshu
            
            var title: String {
                switch self {
                case .otherApps:
                    return ""
                case .bilibili:
                    return String(localized: "Follow us on Bilibili")
                case .xiaohongshu:
                    return String(localized: "Follow us on Xiaohongshu")
                }
            }
            
            var value: String? {
                switch self {
                case .otherApps:
                    return nil
                case .bilibili, .xiaohongshu:
                    return "@App君"
                }
            }
        }
        
        case promotion(String?)
        case thanks
        case settings(GeneralItem)
        case tutorials
        case appjun(AppJunItem)
        case about(AboutItem)
        
        var title: String {
            switch self {
            case .promotion, .thanks:
                return ""
            case .settings(let item):
                return item.title
            case .tutorials:
                return String(localized: "tutorials.title")
            case .appjun(let item):
                return item.title
            case .about(let item):
                return item.title
            }
        }
    }
    
    class DataSource: UITableViewDiffableDataSource<Section, Item> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            let sectionKind = sectionIdentifier(for: section)
            return sectionKind?.header
        }
        
        override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            let sectionKind = sectionIdentifier(for: section)
            return sectionKind?.footer
        }
    }
    
    deinit {
        print("MoreViewController is deinited")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = String(localized: "More")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .automatic
        navigationController?.navigationBar.standardAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label.withAlphaComponent(0.8)]
        navigationController?.navigationBar.tintColor = .systemRed
        view.backgroundColor = .backgroundColor
        
        configureHierarchy()
        configureDataSource()
        reloadData()
        
        if Store.shared.membershipDisplayPrice() == nil {
            retryStoreInfo()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.StoreInfoLoaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.ISOUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.WhiteBalanceUpdated, object: nil)
    }
    
    func configureHierarchy() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .backgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reuseIdentifier")
        tableView.register(PromotionCell.self, forCellReuseIdentifier: NSStringFromClass(PromotionCell.self))
        tableView.register(GratefulCell.self, forCellReuseIdentifier: NSStringFromClass(GratefulCell.self))
        tableView.register(AppCell.self, forCellReuseIdentifier: NSStringFromClass(AppCell.self))
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 50.0
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view)
            make.bottom.equalTo(view)
        }
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self] (tableView, indexPath, item) -> UITableViewCell? in
            guard let self = self else { return nil }
            guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch identifier {
            case .promotion(let price):
                let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(PromotionCell.self), for: indexPath)
                if let cell = cell as? PromotionCell {
                    cell.update(price: price ?? "?.??")
                    cell.purchaseClosure = { [weak self] in
                        self?.lifetimeAction()
                    }
                    cell.restoreClosure = { [weak self] in
                        self?.restorePurchases()
                    }
                }
                return cell
            case .thanks:
                let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(GratefulCell.self), for: indexPath)
                return cell
            case .settings(let item):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = item.value
                cell.contentConfiguration = content
                return cell
            case .tutorials:
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = nil
                cell.contentConfiguration = content
                return cell
            case .appjun(let item):
                switch item {
                case .otherApps(let app):
                    let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(AppCell.self), for: indexPath)
                    if let cell = cell as? AppCell {
                        cell.update(app)
                    }
                    cell.accessoryType = .disclosureIndicator
                    return cell
                default:
                    let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                    cell.accessoryType = .disclosureIndicator
                    var content = UIListContentConfiguration.valueCell()
                    content.text = identifier.title
                    content.textProperties.color = .label
                    content.secondaryText = item.value
                    cell.contentConfiguration = content
                    return cell
                }

            case .about(let item):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = item.value
                cell.contentConfiguration = content
                return cell
            }
        }
    }
    
    @objc
    func reloadData() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.membership])
        switch User.shared.proTier() {
        case .lifetime:
            snapshot.appendItems([.thanks], toSection: .membership)
        case .none:
            snapshot.appendItems([.promotion(Store.shared.membershipDisplayPrice())], toSection: .membership)
        }
        snapshot.appendSections([.settings])
        snapshot.appendItems([.settings(.language), .settings(.iso), .settings(.whiteBalance), .settings(.saveOptions)], toSection: .settings)
        
        snapshot.appendSections([.tutorials])
        snapshot.appendItems([.tutorials], toSection: .tutorials)
        
        snapshot.appendSections([.appjun])
        var appItems: [Item] = [.appjun(.otherApps(.lemon)), .appjun(.otherApps(.offDay)), .appjun(.otherApps(.coconut)), .appjun(.otherApps(.pigeon)), .appjun(.otherApps(.one))]
        if Language.type() == .zh {
            appItems.append(.appjun(.otherApps(.festivals)))
        }
        appItems.append(contentsOf: [.appjun(.bilibili), .appjun(.xiaohongshu)])
        snapshot.appendItems(appItems, toSection: .appjun)
        
        snapshot.appendSections([.about])
        snapshot.appendItems([.about(.specifications), .about(.share), .about(.review), .about(.eula), .about(.privacyPolicy), .about(.email)], toSection: .about)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func scrollToTop() {
        tableView.scrollToRow(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
    }
}

extension MoreViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let item = dataSource.itemIdentifier(for: indexPath) {
            switch item {
            case .promotion:
                break
            case .thanks:
                if let currentWindowScene = view.window?.windowScene {
                    SKStoreReviewController.requestReview(in: currentWindowScene)
                }
            case .settings(let item):
                switch item {
                case .language:
                    jumpToSettings()
                case .iso:
                    enterISOSettings()
                case .whiteBalance:
                    enterWhiteBalanceSettings()
                case .saveOptions:
                    enterWatermarkSettings()
                }
            case .tutorials:
                jumpToTutorials()
            case .appjun(let item):
                switch item {
                case .otherApps(let app):
                    openStorePage(for: app)
                case .bilibili:
                    openBilibiliWebpage()
                case .xiaohongshu:
                    openXiaohongshuWebpage()
                }
            case .about(let item):
                switch item {
                case .specifications:
                    enterSpecifications()
                case .share:
                    shareApp()
                case .review:
                    openAppStoreForReview()
                case .eula:
                    openEULA()
                case .privacyPolicy:
                    openPrivacyPolicy()
                case .email:
                    sendEmailToCustomerSupport()
                }
            }
        }
    }
}

extension MoreViewController {
    func jumpToSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:])
        }
    }
    
    func jumpToTutorials() {
        let tutorialsVC = TutorialsViewController()
        let nav = UINavigationController(rootViewController: tutorialsVC)
        
        navigationController?.present(nav, animated: true)
    }
    
    func enterISOSettings() {
        let isoViewController = ISOOptionsViewController()
        
        navigationController?.pushViewController(isoViewController, animated: true)
    }
    
    func enterWhiteBalanceSettings() {
        let whiteBalanceViewController = WhiteBalanceOptionsViewController()
        
        navigationController?.pushViewController(whiteBalanceViewController, animated: true)
    }
    
    func enterWatermarkSettings() {
        let watermarkViewController = SaveOptionsViewController()
        
        navigationController?.pushViewController(watermarkViewController, animated: true)
    }
    
    func enterSpecifications() {
        let specificationViewController = SpecificationsViewController()
        
        navigationController?.pushViewController(specificationViewController, animated: true)
    }
    
    func sendEmailToCustomerSupport() {
        let recipient = MoreViewController.supportEmail
        
        guard let emailUrlString = "mailto:\(recipient)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let emailUrl = URL(string: emailUrlString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(emailUrl) {
            UIApplication.shared.open(emailUrl, options: [:], completionHandler: nil)
        } else {
            // 打开邮件应用失败，进行适当的处理或提醒用户
        }
    }
    
    func openEULA() {
        if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
            openSF(with: url)
        }
    }
    
    func openPrivacyPolicy() {
        if let url = URL(string: "https://zizicici.medium.com/policy-of-privacy-for-moontake-afc746183ab7") {
            openSF(with: url)
        }
    }
    
    func openBilibiliWebpage() {
        if let url = URL(string: "https://space.bilibili.com/4969209") {
            openSF(with: url)
        }
    }
    
    func openXiaohongshuWebpage() {
        if let url = URL(string: "https://www.xiaohongshu.com/user/profile/63f05fc5000000001001e524") {
            openSF(with: url)
        }
    }
    
    func openYoutubeWebpage() {
        if let url = URL(string: "https://www.youtube.com/@app_jun") {
            openSF(with: url)
        }
    }
    
    func openStorePage(for app: App) {
        guard let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/" + app.storeId) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
        }
    }
    
    func openAppStoreForReview() {
        guard let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id6451189717?action=write-review") else {
            return
        }
        
        if UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
        }
    }
    
    func shareApp() {
        if let url = URL(string: "https://apps.apple.com/app/id6451189717") {
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            present(controller, animated: true)
        }
    }
}

extension MoreViewController {
    func lifetimeAction() {
        showOverlayViewController()
        Task {
            do {
                if let _ = try await Store.shared.purchaseLifetimeMembership() {
                    reloadData()
                }
            }
            catch {
                showAlert(title: String(localized: "membership.failure"), message: error.localizedDescription)
            }
            
            hideOverlayViewController()
        }
    }
    
    func showAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: String(localized: "ok"), style: .cancel)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    func retryStoreInfo() {
        if Store.shared.networkIssueOccurs {
            Store.shared.retryRequestProducts()
        }
    }
    
    func restorePurchases() {
        Task {
            showOverlayViewController()
            await Store.shared.sync()
            hideOverlayViewController()
        }
    }
}
