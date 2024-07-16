//
//  AlbumViewController.swift
//  moontake
//
//  Created by zici on 11/7/24.
//

import UIKit
import SnapKit
import ZCCalendar

class AlbumViewController: UIViewController {
    private var imageInfoDict: [GregorianDay: [ImageInfo]] = [:]
    
    private var dataSource: UICollectionViewDiffableDataSource<GregorianDay, ImageInfo>! = nil
    private var collectionView: UICollectionView! = nil
    
    static let titleElementKind = "titleElementKind"
    static let imageElementKind = "imageElementKind"
    
    deinit {
        print("AlbumViewController is deinited.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateNavigationBarStyle()
        self.title = String(localized: "album.title")
        
        view.backgroundColor = .skyColor
        
        configureHierarchy()
        configureDataSource()
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            self.loadImages()
        }
    }
    
    func updateNavigationBarStyle() {
        navigationController?.navigationBar.prefersLargeTitles = true
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
        collectionView.contentInset = .init(top: 0, left: 0, bottom: 20, right: 0)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
    }
    
    func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<ImageCell, ImageInfo> { (cell, indexPath, item) in
            cell.update(with: item)
        }
        
        dataSource = UICollectionViewDiffableDataSource<GregorianDay, ImageInfo>(collectionView: collectionView) { (collectionView, indexPath, itemIdentifier) -> UICollectionViewCell? in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }
        
        let supplementaryRegistration = UICollectionView.SupplementaryRegistration<TitleSupplementaryView>(elementKind: Self.titleElementKind) { [weak self] (supplementaryView, string, indexPath) in
            guard let self = self else { return }
            guard let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { fatalError("Unknown section") }
            if section == ZCCalendar.manager.today {
                supplementaryView.label.text = String(localized: "today")
            } else {
                supplementaryView.label.text = section.formatString()
            }
        }
        
        dataSource.supplementaryViewProvider = { [weak self] (view, kind, index) in
            guard let self = self else { return nil }
            return self.collectionView.dequeueConfiguredReusableSupplementary(
                using: supplementaryRegistration, for: index)
        }
    }
    
    func loadImages() {
        AlbumManager.shared.fetchAllImages { [weak self] imageInfos in
            self?.updateImages(imageInfos)
        }
    }
    
    func updateImages(_ images: [ImageInfo]) {
        var snapshot = NSDiffableDataSourceSnapshot<GregorianDay, ImageInfo>()
        
        imageInfoDict = images.reduce(into: [GregorianDay: [ImageInfo]]()) { result, image in
            if let creationDay = image.creationDay {
                result[creationDay, default: []].append(image)
            }
        }
        
        for key in imageInfoDict.keys.sorted(by: { $0.julianDay > $1.julianDay }) {
            snapshot.appendSections([key])
            snapshot.appendItems(imageInfoDict[key] ?? [], toSection: key)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

extension AlbumViewController {
    func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { (sectionIndex: Int,
            layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
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

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(
            sectionProvider: sectionProvider, configuration: config)
        return layout
    }
}

extension AlbumViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}
