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

struct EXIF: Hashable, Sendable {
    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
}

class ImageDetailViewController: UIViewController {
    private var imageInfo: ImageInfo!
    private var temporaryPhoto: CapturedPhoto?
    private var captureIsSaved = false
    private var temporaryOriginal: TemporaryPhotoExport?
    private var temporaryPreview: UIImage?
    private var temporaryShare: TemporaryPhotoExport?
    private var temporaryTask: Task<Void, Never>?
    private var temporaryCancellation = LivePhotoCancellation()
    private var preparingShare = false
    
    convenience init(imageInfo: ImageInfo) {
        self.init(nibName: nil, bundle: nil)
        self.imageInfo = imageInfo
    }

    convenience init(temporaryPhoto photo: CapturedPhoto) {
        self.init(capturedPhoto: photo, isSaved: false)
    }

    convenience init(capturedPhoto photo: CapturedPhoto, isSaved: Bool) {
        self.init(imageInfo: ImageInfo(creationTime: photo.date.nanoSecondSince1970,
            dataId: UUID().uuidString, fileType: photo.fileType, width: photo.width, height: photo.height,
            latitude: photo.location?.coordinate.latitude, longitude: photo.location?.coordinate.longitude))
        temporaryPhoto = photo
        captureIsSaved = isSaved
        isModalInPresentation = !isSaved
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
    private var atlasTransition: MoonAtlasTransition?
    private let unsavedNotice = UILabel()
    private let unsavedActionsBackground = UIView()

    private lazy var atlasButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = String(localized: "atlas.title")
        configuration.image = UIImage(systemName: "moon.stars")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityIdentifier = "photo.moonAtlas"
        button.addTarget(self, action: #selector(openMoonAtlas), for: .touchUpInside)
        return button
    }()
    
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
        temporaryTask?.cancel()
        temporaryCancellation.cancel()
        print("ImageDetailViewController is deinited.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .skyColor
        if temporaryPhoto != nil {
            view.accessibilityIdentifier = captureIsSaved ? "photo.sharePreview" : "photo.temporary"
            presentationController?.delegate = self
        }
        
        configureHierarchy()
        configureDataSource()
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            self.loadImage()
        }
        if let photo = temporaryPhoto {
            prepareTemporaryPreview(photo)
        } else {
            Task {
                let url = self.imageInfo.originURL
                self.exif = await Task.detached(priority: .utility) {
                    guard let url, let data = try? Data(contentsOf: url) else { return nil as EXIF? }
                    return Self.getEXIFData(from: data)
                }.value
                self.loadImage()
                self.addButtons()
            }
        }
        moonTitle = String(localized: "moon.phase.loading")
        Task {
            let date = self.imageInfo.creationDate
            let title = await Task.detached(priority: .utility) {
                guard let date else { return String(localized: "moon.phase.unavailable") }
                await MoonManager.shared.prepare(at: date)
                guard let phase = MoonManager.shared.info(at: date) else {
                    return String(localized: "moon.phase.unavailable")
                }
                return String.localizedStringWithFormat(String(localized: "detail.phase.summary"),
                    phase.name, phase.displayIllumination * 100)
            }.value
            self.moonTitle = title
            self.loadImage()
        }
    }
    
    func configureHierarchy() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        // Leave room to scroll photo metadata clear of the persistent actions.
        collectionView.contentInset.bottom = 88
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard unsavedNotice.superview != nil else { return }
        // Keep scrolling metadata above the full footer, including wrapped text
        // at larger accessibility sizes and in longer translations.
        let inset = max(88, view.bounds.maxY - unsavedActionsBackground.frame.minY - view.safeAreaInsets.bottom + 12)
        if abs(collectionView.contentInset.bottom - inset) > 0.5 {
            collectionView.contentInset.bottom = inset
            collectionView.verticalScrollIndicatorInsets.bottom = inset
        }
    }
    
    func configureDataSource() {
        let imageCellRegistration = UICollectionView.CellRegistration<ImageDetailCell, Item> { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            if self.temporaryPhoto != nil {
                cell.updateTemporary(with: self.imageInfo, preview: self.temporaryPreview)
            } else {
                cell.update(with: self.imageInfo)
            }
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
        guard saveButton.superview == nil else { return }
        view.addSubview(atlasButton)
        atlasButton.snp.makeConstraints { make in
            make.centerX.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.height.equalTo(44)
            make.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(68)
            make.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-68)
        }
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
        if temporaryPhoto != nil { configureTemporaryActions() }
    }

    @objc private func openMoonAtlas() {
        guard presentedViewController == nil else { return }
        let source = collectionView.visibleCells.compactMap { $0 as? ImageDetailCell }.first?.imageView
        let atlas = MoonAtlasViewController(imageInfo: imageInfo, previewImage: source?.image)
        let navigation = UINavigationController(rootViewController: atlas)
        atlasTransition = MoonAtlasTransition(source: source)
        navigation.transitioningDelegate = atlasTransition
        navigation.overrideUserInterfaceStyle = .dark
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
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
        if temporaryPhoto != nil, dataSource.snapshot().itemIdentifiers.contains(.image) {
            snapshot.reconfigureItems([.image])
        }
        
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func prepareTemporaryPreview(_ photo: CapturedPhoto) {
        // The existing detail page always previews the original, even when its
        // eventual share/export will contain a watermark.
        let cancellation = temporaryCancellation
        temporaryTask = Task { [weak self] in
            let preview = await Task.detached(priority: .userInitiated) {
                AlbumManager.shared.downsampleImage(for: photo.data, maxSize: 2048)
            }.value
            let original = try? await TemporaryPhotoExport.prepare(photo, target: .origin, cancellation: cancellation)
            guard let self, !Task.isCancelled else { return }
            self.temporaryPreview = preview
            self.temporaryOriginal = original
            self.imageInfo.temporaryOriginalURL = original?.photoURL
            self.imageInfo.temporaryMovieURL = original?.movieURL
            self.exif = Self.getEXIFData(from: photo.data)
            self.loadImage()
            self.addButtons()
            self.atlasButton.isHidden = original?.photoURL == nil
        }
    }

    private func configureTemporaryActions() {
        saveButton.configuration?.image = UIImage(systemName: "square.and.arrow.up")
        saveButton.accessibilityLabel = String(localized: "photo.share.title")
        saveButton.accessibilityIdentifier = "photo.temporary.share"
        saveButton.menu = UIMenu(title: String(localized: "photo.share.title"), children: [
            UIAction(title: String(localized: "photo.watermarked.title"), image: UIImage(systemName: "photo.artframe")) { [weak self] _ in
                self?.shareTemporaryPhoto(target: .watermark)
            },
            UIAction(title: String(localized: "photo.original.title"), image: UIImage(systemName: "photo")) { [weak self] _ in
                self?.shareTemporaryPhoto(target: .origin)
            }
        ])
        deleteButton.configuration?.image = UIImage(systemName: "xmark")
        deleteButton.tintColor = .moonColor
        deleteButton.accessibilityLabel = String(localized: "common.close")
        deleteButton.accessibilityIdentifier = "photo.temporary.close"
        deleteButton.menu = nil
        deleteButton.showsMenuAsPrimaryAction = false
        deleteButton.addTarget(self, action: #selector(closeTemporaryPhoto), for: .touchUpInside)
        if !captureIsSaved { configureUnsavedNotice() }
    }

    private func configureUnsavedNotice() {
        unsavedNotice.text = String(localized: temporaryPhoto?.movieURL == nil
                                    ? "capture.temporary.message" : "capture.temporary.live_message")
        unsavedNotice.font = .preferredFont(forTextStyle: .footnote)
        unsavedNotice.adjustsFontForContentSizeCategory = true
        unsavedNotice.textColor = .moonColor.withAlphaComponent(0.7)
        unsavedNotice.textAlignment = .center
        unsavedNotice.numberOfLines = 0
        unsavedNotice.accessibilityIdentifier = "photo.temporary.notice"
        view.addSubview(unsavedNotice)
        unsavedNotice.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
            make.bottom.equalTo(atlasButton.snp.top).offset(-12)
        }
        // The notice belongs to sharing, so it stays with the actions rather
        // than appearing as another piece of photo metadata.
        unsavedActionsBackground.backgroundColor = .skyColor
        unsavedActionsBackground.isUserInteractionEnabled = false
        view.insertSubview(unsavedActionsBackground, belowSubview: atlasButton)
        unsavedActionsBackground.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalTo(view)
            make.top.equalTo(unsavedNotice.snp.top).offset(-12)
        }
    }

    func shareTemporaryPhoto(target: ImageSaver.TargetType) {
        guard let photo = temporaryPhoto, !preparingShare, presentedViewController == nil else { return }
        if target == .origin && !ProStatus.isPro {
            presentMoontakePaywall(highlighting: .originals) { [weak self] in
                guard ProStatus.isPro, let self, self.viewIfLoaded?.window != nil,
                      !self.isBeingDismissed else { return }
                self.shareTemporaryPhoto(target: target)
            }
            return
        }
        preparingShare = true
        saveButton.isEnabled = false
        saveButton.configuration?.showsActivityIndicator = true
        temporaryCancellation = LivePhotoCancellation()
        let cancellation = temporaryCancellation
        temporaryTask = Task { [weak self] in
            do {
                let export = try await TemporaryPhotoExport.prepare(photo, target: target, cancellation: cancellation)
                try cancellation.check()
                guard let self else { return }
                self.temporaryShare = export
                if self.presentedViewController == nil, !self.isBeingDismissed, self.viewIfLoaded?.window != nil {
                    let activity = UIActivityViewController(
                        activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: export.itemProviders()))
                    activity.popoverPresentationController?.sourceView = self.saveButton
                    // Neither cancel nor share completion discards the temporary capture.
                    activity.completionWithItemsHandler = { [export] _, _, _, _ in withExtendedLifetime(export) {} }
                    self.present(activity, animated: true)
                }
            } catch is CancellationError {
                // Closing the page or leaving the foreground is not an export error.
            } catch {
                self?.showToast(text: String(localized: "capture.prepare_failed"))
            }
            self?.preparingShare = false
            self?.saveButton.isEnabled = true
            self?.saveButton.configuration?.showsActivityIndicator = false
        }
    }

    @objc private func closeTemporaryPhoto() {
        guard presentedViewController == nil else { return }
        if captureIsSaved {
            temporaryTask?.cancel(); temporaryCancellation.cancel()
            dismiss(animated: true)
            return
        }
        let alert = UIAlertController(title: String(localized: "capture.temporary.close_title"),
                                      message: String(localized: "capture.temporary.close_message"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.close"), style: .destructive) { [weak self] _ in
            self?.temporaryTask?.cancel(); self?.temporaryCancellation.cancel()
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    nonisolated static func getEXIFData(from imageData: Data) -> EXIF? {
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
        if ProStatus.isPro {
            savePhoto(for: [.origin])
        } else {
            presentMoontakePaywall(highlighting: .originals)
        }
    }
    
    func saveWatermarkPhoto() {
        let alertController = UIAlertController(title: String(localized: "location.custom.title"), message: String(localized: "location.custom.input.message"), preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = ""
            textField.text = ""
            textField.addTarget(alertController, action: #selector(alertController.textDidChangeInContentAlert), for: .editingChanged)
        }
        let cancelAction = UIAlertAction(title: String(localized: "action.cancel"), style: .cancel) { _ in
        }
        let notSetAction = UIAlertAction(title: String(localized: "detail.location.skip"), style: .default) { [weak self] _ in
            self?.savePhoto(for: [.watermark])
        }
        let setAction = UIAlertAction(title: String(localized: "detail.location.apply"), style: .default) { [weak self] _ in
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
        if imageInfo.hasLivePhoto, let movie = imageInfo.pairedVideoURL {
            saveButton.isEnabled = false; deleteButton.isEnabled = false
            ImageSaver.saveLivePhoto(data, movieURL: movie, targets: targets, fileType: imageInfo.fileType,
                location: imageInfo.location, width: imageInfo.width, height: imageInfo.height, date: creationDate,
                customLocationName: customLocationName, toDatabase: false) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.saveButton.isEnabled = true; self.deleteButton.isEnabled = true
                    switch result {
                    case .success: self.showToast(text: String(localized: "detail.save.toast"))
                    case .failure(let error):
                        LivePhotoRecovery.present(error: error, in: self)
                    }
                }
            }
            return
        }
        ImageSaver.saveImage(data, targets: targets, fileType: imageInfo.fileType, location: imageInfo.location, width: imageInfo.width, height: imageInfo.height, date: creationDate, customLocationName: customLocationName, toDatabase: false) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success: self?.showToast(text: String(localized: "detail.save.toast"))
                case .failure(let error): self?.showToast(text: error.localizedDescription)
                }
            }
        }
    }
    
    func deleteButtonAction() {
        let alertController = UIAlertController(title: String(localized: "detail.alert.delete.title"), message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: String(localized: "action.cancel"), style: .cancel) { _ in
            //
        }
        let deleteAction = UIAlertAction(title: String(localized: "detail.delete.title"), style: .destructive) { [weak self] _ in
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
            if imageInfo.hasLivePhoto, let movie = imageInfo.pairedVideoURL { deleteFile(at: movie) }
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
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ImageDetailCell)?.stopLivePlayback()
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

extension ImageDetailViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        if temporaryPhoto != nil { closeTemporaryPhoto() }
    }
}
