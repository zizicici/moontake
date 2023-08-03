//
//  MoreViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/27.
//

import UIKit
import SnapKit

class MoreViewController: UIViewController {
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
        }
        
        case membership
        case general(GeneralItem)
        case appjun(AppJunItem)
        case about(AboutItem)
        
        var title: String {
            switch self {
            case .membership:
                return ""
            case .general(let item):
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
            case .general(_):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = "value"
                cell.contentConfiguration = content
                return cell
            case .appjun:
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = "value"
                cell.contentConfiguration = content
                return cell
            case .about(_):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = .disclosureIndicator
                var content = UIListContentConfiguration.valueCell()
                content.text = identifier.title
                content.textProperties.color = .label
                content.secondaryText = "value"
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
        snapshot.appendItems([.general(.language), .general(.waterMarkInfo)], toSection: .settings)
        
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
    }
}
