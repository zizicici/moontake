//
//  AlbumViewController.swift
//  moontake
//
//  Created by zici on 11/7/24.
//

import UIKit
import SnapKit
import ZCCalendar
import Kingfisher

class AlbumViewController: UIViewController {
    enum Section: Hashable {
        case day(GregorianDay)
        case hint
    }
    
    enum Item: Hashable {
        case image(ImageInfo)
        case hint(HintInfo)
    }
    
    private var imageInfoDict: [GregorianDay: [ImageInfo]] = [:]
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>! = nil
    private var collectionView: UICollectionView! = nil
    
    static let titleElementKind = "titleElementKind"
    
    deinit {
        KingfisherManager.shared.cache.clearMemoryCache()
        print("AlbumViewController is deinited.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 26.0, *) {
        } else {
            updateNavigationBarStyle()
        }
        
        self.title = String(localized: "album.title")
        
        view.backgroundColor = .skyColor
        
        configureHierarchy()
        configureDataSource()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.DatabaseUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name.LifetimeMemberShip, object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            self.reloadData()
        }
    }
    
    func updateNavigationBarStyle() {
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .automatic
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.moonColor]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.moonColor, .paragraphStyle: style]
        navBarAppearance.backgroundColor = UIColor.skyColor
        navBarAppearance.shadowColor = UIColor.clear
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = UIColor.moonColor
    }
    
    func configureHierarchy() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
    }
    
    func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ImageCell, ImageInfo> { (cell, indexPath, item) in
            cell.update(with: item)
        }
        
        let hintCellRegistration = UICollectionView.CellRegistration<HintCell, HintInfo> { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            cell.update(with: item)
            cell.buttonClosure = { [weak self] in
                self?.jumpToMore()
            }
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { (collectionView, indexPath, itemIdentifier) -> UICollectionViewCell? in
            switch itemIdentifier {
            case .image(let imageInfo):
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: imageInfo)
            case .hint(let hintInfo):
                return collectionView.dequeueConfiguredReusableCell(using: hintCellRegistration, for: indexPath, item: hintInfo)
            }
        }
        
        let supplementaryRegistration = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: Self.titleElementKind) { [weak self] (supplementaryView, string, indexPath) in
            guard let self = self else { return }
            guard let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { fatalError("Unknown section") }
            switch section {
            case .day(let gregorianDay):
                if gregorianDay == ZCCalendar.manager.today {
                    supplementaryView.label.text = String(localized: "today")
                } else {
                    supplementaryView.label.text = gregorianDay.formatString()
                }
            case .hint:
                break
            }
        }
        
        dataSource.supplementaryViewProvider = { [weak self] (view, kind, index) in
            guard let self = self else { return nil }
            guard let section = self.dataSource.sectionIdentifier(for: index.section) else { fatalError("Unknown section") }
            switch section {
            case .day:
                return self.collectionView.dequeueConfiguredReusableSupplementary(using: supplementaryRegistration, for: index)
            case .hint:
                return nil
            }
        }
    }
    
    @objc
    func reloadData() {
        AlbumManager.shared.fetchAllImages { [weak self] imageInfos in
            self?.updateImages(imageInfos)
        }
    }
    
    func updateImages(_ rawImages: [ImageInfo]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        var targetImages: [ImageInfo]
        let targetCount = 12
        if User.shared.proTier() != .lifetime && rawImages.count > targetCount {
            targetImages = Array(rawImages.prefix(targetCount))
        } else {
            targetImages = rawImages
        }
        
        imageInfoDict = targetImages.reduce(into: [GregorianDay: [ImageInfo]]()) { result, image in
            if let creationDay = image.creationDay {
                result[creationDay, default: []].append(image)
            }
        }
        
        for key in imageInfoDict.keys.sorted(by: { $0.julianDay > $1.julianDay }) {
            snapshot.appendSections([.day(key)])
            snapshot.appendItems(imageInfoDict[key]?.compactMap{ .image($0) } ?? [], toSection: .day(key))
        }
        
        snapshot.appendSections([.hint])
        if imageInfoDict.keys.count == 0 {
            snapshot.appendItems([.hint(.empty(User.shared.proTier()))], toSection: .hint)
        } else {
            snapshot.appendItems([.hint(.normal(User.shared.proTier()))], toSection: .hint)
        }
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func jumpToMore() {
        let settingsVC = MoreViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }
}

extension AlbumViewController {
    func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self = self else { return nil }
            guard let section = self.dataSource.sectionIdentifier(for: sectionIndex) else { return nil }
            switch section {
            case .day:
                return getImageSection(layoutEnvironment)
            case .hint:
                return getHintSection(layoutEnvironment)
            }
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider, configuration: config)
        return layout
    }
    
    func getImageSection(_ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(100),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(100),
                                              heightDimension: .absolute(216))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 20
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

        let titleSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(44))
        let titleSupplementary = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: titleSize,
            elementKind: Self.titleElementKind,
            alignment: .top)
        section.boundarySupplementaryItems = [titleSupplementary]
        return section
    }
    
    func getHintSection(_ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(60))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .estimated(60))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let layoutSection = NSCollectionLayoutSection(group: group)
        layoutSection.contentInsets = .zero
        
        return layoutSection
    }
}

extension AlbumViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let item = dataSource.itemIdentifier(for: indexPath) {
            switch item {
            case .image(let imageInfo):
                navigationController?.present(ImageDetailViewController(imageInfo: imageInfo), animated: true)
            case .hint:
                break
            }
        }
    }
}
