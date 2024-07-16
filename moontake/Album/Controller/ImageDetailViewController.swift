//
//  ImageDetailViewController.swift
//  moontake
//
//  Created by zici on 15/7/24.
//

import UIKit
import SnapKit
import ZCCalendar
import ImageIO

struct EXIF: Hashable {
    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
}

class ImageDetailViewController: UIViewController {
    private var imageInfo: ImageInfo!
    
    convenience init(imageInfo: ImageInfo) {
        self.init(nibName: nil, bundle: nil)
        self.imageInfo = imageInfo
    }
    
    enum Section: Hashable {
        case image
        case data
        case action
    }
    
    enum Item: Hashable {
        case image
        case title(String)
        case exif(EXIF)
    }
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>! = nil
    private var collectionView: UICollectionView! = nil
    private var moonTitle: String?
    private var exif: EXIF?
    
    deinit {
        print("ImageDetailViewController is deinited.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .skyColor
        
        configureHierarchy()
        configureDataSource()
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            self.loadImage()
        }
        DispatchQueue.global(qos: .utility).async {
            if let creationDate = self.imageInfo.creationDate {
                let phaseName = MoonManager.shared.getPhaseName(creationDate)
                let phasePercent = MoonManager.shared.getPhasePercent(creationDate)
                self.moonTitle = String(format: "%@ %.1f%%", phaseName, phasePercent * 100)
            }
            self.getImageEXIF()
            DispatchQueue.main.async {
                self.loadImage()
            }
        }
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
        let imageCellRegistration = UICollectionView.CellRegistration<ImageDetailCell, Item> { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            cell.update(with: self.imageInfo)
        }
        let dataCellRegistration = UICollectionView.CellRegistration<TitleAndDateCell, Item> { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            switch item {
            case .image, .exif:
                break
            case .title(let moonTitle):
                cell.moonTitle = moonTitle
            }
            cell.update(with: self.imageInfo)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] (collectionView, indexPath, itemIdentifier) -> UICollectionViewCell? in
            guard let self = self else { return nil }
            guard let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { return nil }
            switch section {
            case .image:
                return collectionView.dequeueConfiguredReusableCell(using: imageCellRegistration, for: indexPath, item: itemIdentifier)
            case .data:
                return collectionView.dequeueConfiguredReusableCell(using: dataCellRegistration, for: indexPath, item: itemIdentifier)
            case .action:
                return collectionView.dequeueConfiguredReusableCell(using: imageCellRegistration, for: indexPath, item: itemIdentifier)
            }
        }
    }
    
    func loadImage() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.image])
        snapshot.appendItems([.image], toSection: .image)
        if let moonTitle = moonTitle {
            snapshot.appendSections([.data])
            snapshot.appendItems([.title(moonTitle)], toSection: .data)
        }
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func getImageEXIF() {
        if let originURL = imageInfo.originURL, let data = try? Data(contentsOf: originURL) {
            self.exif = getEXIFData(from: data)
        }
    }
    
    func getEXIFData(from imageData: Data) -> EXIF? {
        if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) {
            if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
                if let exifData = imageProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    var result = EXIF()
                    if let exposureTime = exifData[kCGImagePropertyExifExposureTime as CFString] as? Double {
                        result.exposureTime = exposureTime
                    }
                    if let fNumber = exifData[kCGImagePropertyExifFNumber as CFString] as? Double {
                        result.fNumber = fNumber
                    }
                    if let isoRaings = exifData[kCGImagePropertyExifISOSpeedRatings as CFString] as? [Int] {
                        result.iso = isoRaings.first
                    }
                    return result
                } else {
                    print("404")
                }
            }
        }
        return nil
    }
}

extension ImageDetailViewController {
    func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            guard let self = self else { return nil }
            guard let section = self.dataSource.sectionIdentifier(for: sectionIndex) else { return nil }

            switch section {
            case .image:
                return self.getImageSection(layoutEnvironment)
            case .data:
                return self.getDataSection(layoutEnvironment)
            case .action:
                return self.getImageSection(layoutEnvironment)
            }
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 20

        let layout = UICollectionViewCompositionalLayout(sectionProvider: sectionProvider, configuration: config)
        return layout
    }
    
    func getImageSection(_ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let width = layoutEnvironment.container.effectiveContentSize.width
        let height = floor(width / CGFloat(self.imageInfo.width) * CGFloat(self.imageInfo.height))
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(width),
                                              heightDimension: .absolute(height))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let layoutSection = NSCollectionLayoutSection(group: group)
        layoutSection.contentInsets = .zero
        
        return layoutSection
    }
    
    func getDataSection(_ layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(100))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .estimated(100))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let layoutSection = NSCollectionLayoutSection(group: group)
        layoutSection.contentInsets = .zero
        
        return layoutSection
    }
}

extension ImageDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}
