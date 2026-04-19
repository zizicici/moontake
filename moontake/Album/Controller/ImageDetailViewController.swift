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
import Toast
import MoreKit

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
    }
    
    enum Item: Hashable {
        case image
        case title(String)
        case exif
    }
    
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>! = nil
    private var collectionView: UICollectionView! = nil
    private var moonTitle: String?
    private var exif: EXIF?
    
    private let deleteButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "trash")

        let button = UIButton(configuration: configuration)
        button.tintColor = .systemRed
        button.accessibilityLabel = String(localized: "detail.delete.title")
        button.showsMenuAsPrimaryAction = true
        
        return button
    }()
    
    private let saveButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        if #available(iOS 17.0, *) {
            configuration.image = UIImage(systemName: "photo.badge.arrow.down")
        } else {
            configuration.image = UIImage(systemName: "photo")
        }

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "detail.save.title")
        button.showsMenuAsPrimaryAction = true

        return button
    }()
    
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
                self.addButtons()
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
        let exifCellRegistration = UICollectionView.CellRegistration<EXIFCell, Item> { [weak self] (cell, indexPath, item) in
            guard let self = self , let exif = self.exif else { return }
            cell.update(with: exif)
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { (collectionView, indexPath, itemIdentifier) -> UICollectionViewCell? in
            switch itemIdentifier {
            case .image:
                return collectionView.dequeueConfiguredReusableCell(using: imageCellRegistration, for: indexPath, item: itemIdentifier)
            case .title:
                return collectionView.dequeueConfiguredReusableCell(using: dataCellRegistration, for: indexPath, item: itemIdentifier)
            case .exif:
                return collectionView.dequeueConfiguredReusableCell(using: exifCellRegistration, for: indexPath, item: itemIdentifier)
            }
        }
    }
    
    func addButtons() {
        view.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.leading.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.width.height.equalTo(44)
        }
        let orginAction = UIAction(title: String(localized: "photo.original.title"), image: UIImage(systemName: "photo")) { [weak self] _ in
            guard let self = self else { return }
            self.saveOriginPhoto()
        }
        let watermarkAction = UIAction(title: String(localized: "photo.watermarked.title"), image: UIImage(systemName: "photo.artframe")) { [weak self] _ in
            guard let self = self else { return }
            self.saveWatermarkPhoto()
        }
        saveButton.menu = UIMenu(title: String(localized: "detail.save.title"), children: [watermarkAction, orginAction])
        
        view.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.width.height.equalTo(44)
        }
        let deleteAction = UIAction(title: String(localized: "detail.delete.title"), image: UIImage(systemName: "trash"), attributes: [.destructive]) { [weak self] _ in
            guard let self = self else { return }
            self.deleteButtonAction()
        }
        deleteButton.menu = UIMenu(title: "", children: [deleteAction])
    }
    
    func loadImage() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.image])
        snapshot.appendItems([.image], toSection: .image)
        if let moonTitle = moonTitle {
            snapshot.appendSections([.data])
            snapshot.appendItems([.title(moonTitle)], toSection: .data)
            if exif != nil {
                snapshot.appendItems([.exif], toSection: .data)
            }
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
    
    func saveOriginPhoto() {
        if User.shared.proTier() == .lifetime {
            savePhoto(for: [.origin])
        } else {
            let alertController = UIAlertController(title: String(localized: "detail.alert.membership.title"), message: nil, preferredStyle: .actionSheet)
            let cancelAction = UIAlertAction(title: String(localized: "cancel"), style: .cancel) { _ in
                //
            }
            let learnMoreAction = UIAlertAction(title: String(localized: "membership.learnMore"), style: .default) { [weak self] _ in
                self?.jumpToMore()
            }

            alertController.addAction(cancelAction)
            alertController.addAction(learnMoreAction)
            alertController.popoverPresentationController?.sourceView = saveButton
            present(alertController, animated: true, completion: nil)
        }
    }
    
    func saveWatermarkPhoto() {
        let alertController = UIAlertController(title: String(localized: "detail.location.input.title"), message: String(localized: "detail.location.input.message"), preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = ""
            textField.text = ""
            textField.addTarget(alertController, action: #selector(alertController.textDidChangeInContentAlert), for: .editingChanged)
        }
        let cancelAction = UIAlertAction(title: String(localized: "cancel"), style: .cancel) { _ in
        }
        let notSetAction = UIAlertAction(title: String(localized: "detail.location.notSet"), style: .default) { [weak self] _ in
            self?.savePhoto(for: [.watermark])
        }
        let setAction = UIAlertAction(title: String(localized: "detail.location.set"), style: .default) { [weak self] _ in
            if let text = alertController.textFields?.first?.text {
                self?.savePhoto(for: [.watermark], customLocationName: text)
            } else {
                //
            }
        }
        setAction.isEnabled = false

        alertController.addAction(cancelAction)
        alertController.addAction(notSetAction)
        alertController.addAction(setAction)
        present(alertController, animated: true, completion: nil)
    }
    
    func savePhoto(for targets: [ImageSaver.TargetType], customLocationName: String? = nil) {
        guard let originURL = imageInfo.originURL, let data = try? Data(contentsOf: originURL), let creationDate = imageInfo.creationDate else {
            return
        }
        ImageSaver.saveImage(data, targets: targets, fileType: imageInfo.fileType, location: imageInfo.location, width: imageInfo.width, height: imageInfo.height, date: creationDate, customLocationName: customLocationName, toDatabase: false) { [weak self] in
            DispatchQueue.main.async {
                self?.showToast(text: String(localized: "detail.save.toast"))
            }
        }
    }
    
    func deleteButtonAction() {
        let alertController = UIAlertController(title: String(localized: "detail.alert.delete.title"), message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: String(localized: "cancel"), style: .cancel) { _ in
            //
        }
        let deleteAction = UIAlertAction(title: String(localized: "detail.alert.delete.confirm"), style: .destructive) { [weak self] _ in
            self?.deleteAction()
        }

        alertController.addAction(cancelAction)
        alertController.addAction(deleteAction)
        alertController.popoverPresentationController?.sourceView = deleteButton
        present(alertController, animated: true, completion: nil)
    }
    
    func deleteAction() {
        let fileURL = imageInfo.originURL
        let thumbnailURL = imageInfo.thumbnailURL
        let result = AppDatabase.shared.delete(imageInfo: imageInfo)
        if result {
            // Delete Data File and Thumbnail
            if let fileURL = fileURL {
                deleteFile(at: fileURL)
            }
            if let thumbnailURL = thumbnailURL {
                deleteFile(at: thumbnailURL)
            }
            // Exit
            dismiss(animated: true)
        }
    }
    
    func deleteFile(at url: URL) {
        let fileManager = FileManager.default
        
        do {
            try fileManager.removeItem(at: url)
            print("File deleted successfully.")
        } catch {
            print("Error deleting file: \(error.localizedDescription)")
        }
    }
    
    func showToast(text: String) {
        view.hideAllToasts()
        var style = ToastStyle()
        style.backgroundColor = .black.withAlphaComponent(0.8)
        style.messageAlignment = .center
        style.messageFont = UIFont.systemFont(ofSize: 14)
        style.messageColor = .moonColor
        view.makeToast(text, duration: 0.5, position: .center, title: nil, image: nil, style: style, completion: nil)
    }
    
    func jumpToMore() {
        let settingsVC = makeMorePageViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
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
