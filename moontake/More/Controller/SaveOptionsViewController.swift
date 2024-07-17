//
//  SaveOptionsViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/9.
//

import UIKit
import SnapKit

class SaveOptionsViewController: UIViewController {
    private var tableView: UITableView!
    private var dataSource: DataSource!
    
    enum Section: Hashable {
        case save
        
        var header: String? {
            switch self {
            case .save:
                return String(localized: "settings.save.photoLibrary")
            }
        }
        
        var footer: String? {
            switch self {
            case .save:
                if User.shared.proTier() == .lifetime {
                    return nil
                } else {
                    return String(localized: "For free users, the default option is automatically selected and not customizable.")
                }
            }
        }
    }
    
    enum Item: Hashable {
        case save(Settings.SaveToAlbumOption, Bool)
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
        
        self.title = String(localized: "Photo Save Options")
        
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
            case .save(let item, let isSelected):
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
        snapshot.appendSections([.save])
        let saveToAlbumSettings = Settings.shared.getSaveToAlbumSettings()
        snapshot.appendItems([.save(.photoWithoutWatermark, saveToAlbumSettings == .photoWithoutWatermark), .save(.photoWithWatermark, saveToAlbumSettings == .photoWithWatermark), .save(.both, saveToAlbumSettings == .both)], toSection: .save)
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension SaveOptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return }
        switch identifier {
        case .save(let item, _):
            let result = Settings.shared.save(option: item)
            if !result {
                showUserTierAlert()
            }
        }
        self.reloadData()
    }
}

extension SaveOptionsViewController {
    func showUserTierAlert() {
        showAlert(title: String(localized: "This option is only for Pro user."), message: nil)
    }
    
    func showAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: String(localized: "OK"), style: .cancel)
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
