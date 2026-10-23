import PhotosUI
import UIKit

/// Loads only the visible album item. PhotosUI supplies the standard press-and-hold gesture.
final class LivePhotoPlaybackView: UIView {
    private let liveView = PHLivePhotoView()
    private let badge = UIImageView(image: PHLivePhotoView.livePhotoBadgeImage(options: .overContent))
    private var request: PHLivePhotoRequestID?
    private var dataID: String?
    private var resources: LivePhotoResources?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        liveView.contentMode = .scaleAspectFit
        liveView.isMuted = false
        addSubview(liveView)
        addSubview(badge)
        accessibilityLabel = String(localized: "live_photo.play")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let request { PHLivePhoto.cancelRequest(withRequestID: request) } }
    override func layoutSubviews() {
        super.layoutSubviews()
        liveView.frame = bounds
        badge.frame = CGRect(x: 12, y: 12, width: 28, height: 28)
    }
    func load(_ info: ImageInfo) {
        guard dataID != info.dataId else { return }
        reset()
        guard info.hasLivePhoto, let photo = info.originURL, let movie = info.pairedVideoURL else { return }
        guard let resources = try? LivePhotoResources(),
            let namedPhoto = try? resources.playbackStill(from: photo, fileType: info.fileType)
        else { return }
        self.resources = resources
        dataID = info.dataId
        let id = info.dataId
        let target = UIScreen.main.bounds.size.applying(
            CGAffineTransform(scaleX: UIScreen.main.scale, y: UIScreen.main.scale))
        request = PHLivePhoto.request(
            withResourceFileURLs: [namedPhoto, movie], placeholderImage: nil, targetSize: target,
            contentMode: .aspectFit
        ) { [weak self, resources] livePhoto, info in
            _ = resources  // Keep files alive through request completion/cancellation.
            DispatchQueue.main.async {
                guard let self, self.dataID == id, let livePhoto,
                    (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true
                else { return }
                self.liveView.livePhoto = livePhoto
                self.isHidden = false
            }
        }
    }
    func stopPlayback() { liveView.stopPlayback() }
    func reset() {
        if let request { PHLivePhoto.cancelRequest(withRequestID: request) }
        request = nil
        dataID = nil
        liveView.stopPlayback()
        liveView.livePhoto = nil
        isHidden = true
        resources = nil
    }
}
