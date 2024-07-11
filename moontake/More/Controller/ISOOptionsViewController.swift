//
//  ISOOptionsViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/9/5.
//

import UIKit
import SnapKit

class ISOOptionsViewController: UIViewController {
    private var tableView: UITableView!
    private var dataSource: DataSource!
    
    enum Section: Hashable {
        case iso
        
        var header: String? {
            switch self {
            default:
                return nil
            }
        }
        
        var footer: String? {
            return String(localized: "In theory, under the same exposure time, a lower ISO value tends to reduce image noise.\nHowever, a lower ISO value may result in longer exposure time, which often requires a more stable camera support to avoid potential blurriness in the image.")
        }
    }
    
    enum Item: Hashable {
        case iso(Settings.ISOOption, Bool)
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
        
        self.title = String(localized: "ISO Options")
        
        view.backgroundColor = UIColor.backgroundColor
        navigationItem.largeTitleDisplayMode = .never
        
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
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self] (tableView, indexPath, item) -> UITableViewCell? in
            guard let self = self else { return nil }
            guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return nil }
            switch identifier {
            case .iso(let item, let isSelected):
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
        snapshot.appendSections([.iso])
        let isoSettings = Settings.shared.getISOSettings()
        switch isoSettings {
        case .default:
            snapshot.appendItems([.iso(.default, true)])
            let array = Camera.shared.getISOCandidates()
            snapshot.appendItems(array.map{ .iso(.value($0), false) })
        case .value(let isoValue):
            snapshot.appendItems([.iso(.default, false)])
            let array = Camera.shared.getISOCandidates()
            snapshot.appendItems(array.map{ .iso(.value($0), isoValue == $0) })
        }
        
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension ISOOptionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return }
        switch identifier {
        case .iso(let item, _):
            Settings.shared.save(option: item)
        }
        
        self.reloadData()
    }
}
