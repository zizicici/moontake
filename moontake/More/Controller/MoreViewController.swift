//
//  MoreViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/27.
//

import UIKit
import SnapKit
import SafariServices

class MoreViewController: UIViewController {
    static let supportEmail = "moon@zi.ci"

    private var tableView: UITableView!
    private var dataSource: DataSource!
    
    enum Section: Hashable {
        case membership
        case settings
        case appjun
        case about
        
        var header: String? {
            switch self {
            case .membership:
                return " "
            case .settings:
                return "Settings".localized()
            case .appjun:
                return "App from AppJun".localized()
            case .about:
                return "About".localized()
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
            case saveOptions
            
            var title: String {
                switch self {
                case .language:
                    return "Language".localized()
                case .iso:
                    return "ISO".localized()
                case .saveOptions:
                    return "Photo Save Options".localized()
                }
            }
            
            var value: String? {
                switch self {
                case .language:
                    return "🍋Language".localized()
                case .iso:
                    return Settings.shared.getISOSettings().title
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
                    return "Specifications".localized()
                case .share:
                    return "Share App".localized()
                case .review:
                    return "Write Review".localized()
                case .eula:
                    return "EULA".localized()
                case .privacyPolicy:
                    return "Policy of Privacy".localized()
                case .email:
                    return "Email".localized()
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
        
        enum AppJunItem {
            case otherApps
            case bilibili
            case xiaohongshu
            
            var title: String {
                switch self {
                case .otherApps:
                    return ""
                case .bilibili:
                    return "Follow us on Bilibili".localized()
                case .xiaohongshu:
                    return "Follow us on Xiaohongshu".localized()
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
        
        case membership(MembershipCell.DisplayItem)
        case settings(GeneralItem)
        case appjun(AppJunItem)
        case about(AboutItem)
        
        var title: String {
            switch self {
            case .membership:
                return ""
            case .settings(let item):
                return item.title
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "More".localized()
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .automatic
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.firstLineHeadIndent = 10
        navigationController?.navigationBar.standardAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label.withAlphaComponent(0.8), .paragraphStyle: style]
        navigationController?.navigationBar.tintColor = .systemRed
        view.backgroundColor = .backgroundColor
        
        configureHierarchy()
        configureDataSource()
        reloadData()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.StoreInfoLoaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.ISOUpdated, object: nil)
    }
    
    func configureHierarchy() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .backgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reuseIdentifier")
        tableView.register(MembershipCell.self, forCellReuseIdentifier: NSStringFromClass(MembershipCell.self))
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
            case .membership:
                let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(MembershipCell.self), for: indexPath)
                if let cell = cell as? MembershipCell {
                    if case let Item.membership(displayItem) = identifier {
                        cell.update(item: displayItem)
                    }
                    
                    cell.lifetimeClosure = { [weak self] in
                        self?.lifetimeAction()
                    }
                    cell.manageClosure = { [weak self] in
                        self?.manageAction()
                    }
                }
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
            case .appjun(let item):
                switch item {
                case .otherApps:
                    let cell = tableView.dequeueReusableCell(withIdentifier: NSStringFromClass(AppCell.self), for: indexPath)
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
        if Store.shared.networkIssueOccurs {
            snapshot.appendItems([.membership(MembershipCell.DisplayItem(type: .issue))], toSection: .membership)
        } else {
            snapshot.appendItems([.membership(MembershipCell.DisplayItem(type: .tier(User.shared.proTier()), membership: Store.shared.membershipDisplayPrice()))], toSection: .membership)
        }
        snapshot.appendSections([.settings])
        snapshot.appendItems([.settings(.language), .settings(.iso), .settings(.saveOptions)], toSection: .settings)
        
        snapshot.appendSections([.appjun])
        snapshot.appendItems([.appjun(.otherApps), .appjun(.bilibili), .appjun(.xiaohongshu)], toSection: .appjun)
        
        snapshot.appendSections([.about])
        snapshot.appendItems([.about(.specifications), .about(.share), .about(.review), .about(.eula), .about(.privacyPolicy), .about(.email)], toSection: .about)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension MoreViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let item = dataSource.itemIdentifier(for: indexPath) {
            switch item {
            case .membership:
                break
            case .settings(let item):
                switch item {
                case .language:
                    jumpToSettings()
                case .iso:
                    enterISOSettings()
                case .saveOptions:
                    enterWatermarkSettings()
                }
            case .appjun(let item):
                switch item {
                case .otherApps:
                    openLemonStorePage()
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
    
    func enterISOSettings() {
        let isoViewController = ISOOptionsViewController()
        
        navigationController?.pushViewController(isoViewController, animated: true)
    }
    
    func enterWatermarkSettings() {
        let watermarkViewController = WatermarkViewController()
        
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
    
    func openLemonStorePage() {
        guard let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id6449700998") else {
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
                showAlert(title: "Order Failure".localized(), message: error.localizedDescription)
            }
            
            hideOverlayViewController()
        }
    }
    
    func showAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "OK".localized(), style: .cancel)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    func manageAction() {
        if Store.shared.networkIssueOccurs {
            Store.shared.retryRequestProducts()
        } else {
            switch User.shared.proTier() {
            case .lifetime:
                restorePurchases()
            case .none:
                restorePurchases()
            }
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

extension MoreViewController {
    func showOverlayViewController() {
        let overlayVC = OverlayViewController()
        
        // 让当前视图控制器的内容可见但不可交互
        overlayVC.modalPresentationStyle = .overCurrentContext
        overlayVC.modalTransitionStyle = .crossDissolve
        
        // 显示覆盖全屏的遮罩层
        present(overlayVC, animated: true, completion: nil)
    }

    func hideOverlayViewController() {
        // 隐藏覆盖全屏的遮罩层
        dismiss(animated: true, completion: nil)
    }
}

class OverlayViewController: UIViewController {
    let activityIndicator = UIActivityIndicatorView(style: .large)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 设置背景颜色和透明度
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        
        // 添加指示器到视图并居中
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // 开始旋转
        activityIndicator.startAnimating()
    }
}
