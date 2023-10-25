//
//  WatermarkViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import UIKit
import SnapKit
import CoreLocation

class WatermarkViewController: UIViewController {
    private var tableView: UITableView!
    private var dataSource: DataSource!
    
    enum Section: Hashable {
        case location
        case save
        case watermark
        
        var header: String? {
            switch self {
            case .location:
                return "Location".localized()
            case .save:
                return "Save to Album".localized()
            case .watermark:
                return "Right Side Watermark".localized()
            }
        }
        
        var footer: String? {
            switch self {
            case .location:
                return nil
            case .save:
                if User.shared.proTier() == .lifetime {
                    return nil
                } else {
                    return "For free users, the default option is automatically selected and not customizable.".localized()
                }
            case .watermark:
                if User.shared.proTier() == .lifetime {
                    return nil
                } else {
                    return "The App Icon watermark is only for Pro User.".localized()
                }
            }
        }
    }
    
    enum Item: Hashable {
        case location(CLAuthorizationStatus)
        case save(Settings.SaveToAlbumOption, Bool)
        case watermark(Settings.WatermarkTypeOption, Bool)
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
        
        self.title = "Photo Save Options".localized()
        
        view.backgroundColor = UIColor.backgroundColor
        navigationItem.largeTitleDisplayMode = .never
        
        configureHierarchy()
        configureDataSource()
        reloadData()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .LocationAuthorizationDidChanged, object: nil)
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
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self] (tableView, indexPath, item) -> UITableViewCell? in
            guard let self = self else { return nil }
            guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch identifier {
            case .location(let authorizationStatus):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                var content = UIListContentConfiguration.valueCell()
                switch authorizationStatus {
                case .notDetermined:
                    content.text = "Requst Authorization".localized()
                case .restricted, .denied:
                    content.text = "Location".localized()
                    content.secondaryText = "Never".localized()
                case .authorizedAlways, .authorizedWhenInUse:
                    content.text = "Location".localized()
                    content.secondaryText = "While Using the App".localized()
                @unknown default:
                    break
                }
                content.textProperties.color = .label
                cell.contentConfiguration = content
                return cell
            case .save(let item, let isSelected):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = isSelected ? .checkmark : .none
                cell.tintColor = .systemRed
                var content = UIListContentConfiguration.valueCell()
                content.text = item.title
                content.textProperties.color = .label
                cell.contentConfiguration = content
                return cell
            case .watermark(let item, let isSelected):
                let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)
                cell.accessoryType = isSelected ? .checkmark : .none
                cell.tintColor = .systemRed
                var content = UIListContentConfiguration.valueCell()
                content.text = item.title
                content.textProperties.color = .label
                cell.contentConfiguration = content
                return cell
            }
        }
    }
    
    @objc
    func reloadData() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.location])
        snapshot.appendItems([.location(Location.shared.authorizationStatus())], toSection: .location)
        snapshot.appendSections([.save])
        let saveToAlbumSettings = Settings.shared.getSaveToAlbumSettings()
        snapshot.appendItems([.save(.photoWithWatermark, saveToAlbumSettings == .photoWithWatermark), .save(.photoWithoutWatermark, saveToAlbumSettings == .photoWithoutWatermark), .save(.both, saveToAlbumSettings == .both)], toSection: .save)
        snapshot.appendSections([.watermark])
        let watermarkTypeSettings = Settings.shared.getWatermarkTypeSettings()
        snapshot.appendItems([.watermark(.qrCode, watermarkTypeSettings == .qrCode), .watermark(.icon, watermarkTypeSettings == .icon), .watermark(.blank, watermarkTypeSettings == .blank)], toSection: .watermark)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension WatermarkViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return }
        switch identifier {
        case .location(let authorizationStatus):
            switch authorizationStatus {
            case .notDetermined:
                Location.shared.requestAuthorization()
            case .restricted, .denied:
                jumpToSettings()
            case .authorizedAlways, .authorizedWhenInUse:
                jumpToSettings()
            @unknown default:
                break
            }
        case .save(let item, _):
            let result = Settings.shared.save(option: item)
            if !result {
                showUserTierAlert()
            }
        case .watermark(let item, _):
            let result = Settings.shared.save(option: item)
            if !result {
                showUserTierAlert()
            }
        }
        self.reloadData()
    }
}

extension WatermarkViewController {
    func showUserTierAlert() {
        showAlert(title: "This option is only for Pro user.".localized(), message: nil)
    }
    
    func showAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "OK".localized(), style: .cancel)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }
    
    func jumpToSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
           return
        }
        if UIApplication.shared.canOpenURL(url) {
           UIApplication.shared.open(url, options: [:])
        }
    }
}
