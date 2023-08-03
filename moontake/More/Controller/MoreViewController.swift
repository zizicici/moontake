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
                return "Membership".localized()
            case .settings:
                return "Settings".localized()
            case .appjun:
                return "AppJun".localized()
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
            case waterMarkInfo
            case enableRaw
            
            var title: String {
                switch self {
                case .language:
                    return "Language".localized()
                case .waterMarkInfo:
                    return "Watermark".localized()
                case .enableRaw:
                    return "Enable Raw".localized()
                }
            }
            
            var value: String? {
                switch self {
                case .language:
                    return "🍋Language".localized()
                default:
                    return nil
                }
            }
        }
        
        enum AboutItem {
            case specifications
            case eula
            case privacyPolicy
            case email
            
            var title: String {
                switch self {
                case .specifications:
                    return "Specifications".localized()
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
                    return "Other Apps".localized()
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
        
        case membership
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
    }
    
    func configureHierarchy() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .backgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reuseIdentifier")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 50.0
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view)
            make.bottom.equalTo(view)
        }
        tableView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
    }
    
    func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self] (tableView, indexPath, item) -> UITableViewCell? in
            guard let self = self else { return nil }
            guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch identifier {
            case .membership:
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .none
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
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = item.value
                cell.contentConfiguration = content
                return cell
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
        snapshot.appendItems([.membership], toSection: .membership)
        
        snapshot.appendSections([.settings])
        snapshot.appendItems([.settings(.language), .settings(.waterMarkInfo)], toSection: .settings)
        
        snapshot.appendSections([.appjun])
        snapshot.appendItems([.appjun(.otherApps), .appjun(.bilibili), .appjun(.xiaohongshu)], toSection: .appjun)
        
        snapshot.appendSections([.about])
        snapshot.appendItems([.about(.specifications), .about(.eula), .about(.privacyPolicy), .about(.email)], toSection: .about)
        
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
                case .waterMarkInfo:
                    break
                case .enableRaw:
                    break
                }
            case .appjun(let item):
                switch item {
                case .otherApps:
                    break
                case .bilibili:
                    openBilibiliWebpage()
                case .xiaohongshu:
                    openXiaohongshuWebpage()
                }
            case .about(let item):
                switch item {
                case .specifications:
                    enterSpecifications()
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
        if let url = URL(string: "https://zizicici.medium.com/policy-of-privacy-for-a-lemon-diary-c4b49b020647") {
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
}
