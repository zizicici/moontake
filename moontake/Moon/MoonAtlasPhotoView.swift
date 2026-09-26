import UIKit
import SkyKit

/// The photograph stays in a normal zoomable scroll view. Labels live above the
/// scroll view so their text and tap targets keep a constant size while zooming.
final class MoonAtlasPhotoView: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let referenceView = UIImageView()
    private let overlay = MoonAtlasLabelsView()
    private let guide = CAShapeLayer()
    private var viewport: CGSize = .zero
    private var isMoonFocused = false
    private var fit: MoonAtlasFit?
    private var surface: MoonSurface?
    private var features: [MoonAtlasFeature] = []
    private var labelsVisible = false
    private var focusAnimator: UIViewPropertyAnimator?
    private var movingPhoto: UIView?
    private var focusCompletion: ((Bool) -> Void)?
    var displayedImage: UIImage? { imageView.image }
    var visibleAnnotationCount: Int { overlay.visibleAnnotationCount }
    var onFeature: ((MoonAtlasFeature) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var selectedFeatureID: String? { didSet { updateOverlay() } }
    var showsReference = false { didSet { referenceView.isHidden = !showsReference } }
    var isAdjusting = false {
        didSet {
            scrollView.isScrollEnabled = !isAdjusting
            adjustmentPan.isEnabled = isAdjusting
            guide.isHidden = !isAdjusting
            updateOverlay()
        }
    }
    private lazy var adjustmentPan = UIPanGestureRecognizer(target: self, action: #selector(moveAlignment(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        accessibilityIdentifier = "atlas.photo"
        scrollView.delegate = self
        // Top-bar taps must not scroll a zoomed photograph back to its origin.
        scrollView.scrollsToTop = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        addSubview(scrollView)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        referenceView.alpha = 0.48
        referenceView.isHidden = true
        imageView.addSubview(referenceView)
        addSubview(overlay)
        overlay.onFeature = { [weak self] in self?.onFeature?($0) }
        guide.strokeColor = UIColor.moonColor.withAlphaComponent(0.7).cgColor
        guide.fillColor = UIColor.clear.cgColor
        guide.lineWidth = 1
        guide.lineDashPattern = [3, 5]
        guide.isHidden = true
        overlay.layer.addSublayer(guide)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        addGestureRecognizer(adjustmentPan)
        adjustmentPan.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPhoto(_ image: UIImage) {
        // A replacement may arrive after the preview has already been zoomed.
        // Reset that transform before assigning a frame in image coordinates.
        scrollView.minimumZoomScale = 1
        scrollView.setZoomScale(1, animated: false)
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        viewport = .zero
        isMoonFocused = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    func setResult(_ result: MoonAtlasResult, showLabels: Bool = true) {
        surface = result.surface
        features = result.features
        referenceView.image = result.reference
        update(fit: result.fit, showLabels: showLabels && result.fit.accepted == true)
    }

    func displayedImageFrame(in view: UIView) -> CGRect? {
        MoonAtlasPhotoGeometry.imageFrame(imageView, in: view)
    }

    /// Animate a single photograph while the scroll view settles at its final
    /// zoom. This gives us a real completion boundary before revealing labels.
    func focusForEntrance(animated: Bool, completion: @escaping (Bool) -> Void) {
        cancelEntrance()
        guard animated, let image = imageView.image, let start = displayedImageFrame(in: self) else {
            focusOnMoon(animated: false); completion(true); return
        }
        let moving = UIImageView(image: image)
        moving.accessibilityIdentifier = "atlas.focusingPhoto"
        moving.contentMode = .scaleAspectFit
        moving.frame = start
        insertSubview(moving, belowSubview: overlay)
        movingPhoto = moving
        scrollView.isHidden = true
        focusOnMoon(animated: false)
        guard let end = displayedImageFrame(in: self) else {
            moving.removeFromSuperview(); movingPhoto = nil; scrollView.isHidden = false
            completion(false); return
        }
        focusCompletion = completion
        let animator = UIViewPropertyAnimator(duration: 0.65, curve: .easeInOut) { moving.frame = end }
        animator.addCompletion { [weak self] position in
            guard let self else { return }
            self.movingPhoto?.removeFromSuperview(); self.movingPhoto = nil
            self.scrollView.isHidden = false; self.focusAnimator = nil
            let completion = self.focusCompletion; self.focusCompletion = nil
            completion?(position == .end)
        }
        focusAnimator = animator
        animator.startAnimation()
    }

    func revealAnnotations(animated: Bool, completion: @escaping () -> Void) {
        overlay.prepareReveal()
        labelsVisible = fit?.accepted == true
        updateOverlay()
        overlay.reveal(animated: animated, completion: completion)
    }

    func cancelEntrance() {
        // If the user closes mid-zoom, start the return transition from the
        // photograph's current on-screen position, not the unfinished target.
        let currentFrame = focusAnimator == nil ? nil : movingPhoto?.layer.presentation()?.frame
        focusAnimator?.stopAnimation(true); focusAnimator = nil
        if let currentFrame, let image = imageView.image, image.size.width > 0 {
            scrollView.setZoomScale(currentFrame.width / image.size.width, animated: false)
            centerImage()
            scrollView.contentOffset = CGPoint(x: imageView.frame.minX - currentFrame.minX,
                                               y: imageView.frame.minY - currentFrame.minY)
        }
        movingPhoto?.removeFromSuperview(); movingPhoto = nil
        scrollView.isHidden = false
        let completion = focusCompletion; focusCompletion = nil
        completion?(false)
        overlay.cancelReveal()
    }

    func update(fit: MoonAtlasFit, showLabels: Bool) {
        self.fit = fit
        labelsVisible = showLabels
        referenceView.transform = .identity
        referenceView.bounds = CGRect(x: 0, y: 0, width: fit.radius * 2, height: fit.radius * 2)
        referenceView.center = CGPoint(x: fit.x, y: fit.y)
        referenceView.transform = CGAffineTransform(rotationAngle: fit.rotation * .pi / 180)
            .concatenating(CGAffineTransform(scaleX: fit.mirror == true ? -1 : 1, y: 1))
        updateOverlay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        overlay.frame = bounds
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if viewport != bounds.size {
            viewport = bounds.size
            scrollView.minimumZoomScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            scrollView.maximumZoomScale = max(20, scrollView.minimumZoomScale * 30)
            if isMoonFocused { focusOnMoon(animated: false) }
            else { scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false) }
        }
        centerImage()
        updateOverlay()
    }

    func focusOnMoon(animated: Bool) {
        guard let fit, fit.radius > 0 else { return }
        isMoonFocused = true
        guard bounds.width > 0, bounds.height > 0 else { setNeedsLayout(); return }
        let desired = min(bounds.width * 0.76, bounds.height * 0.75) / (fit.radius * 2)
        let scale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale, desired))
        if animated {
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            scrollView.zoom(to: CGRect(x: fit.x - size.width / 2, y: fit.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
        } else {
            scrollView.setZoomScale(scale, animated: false)
            centerImage()
            let point = CGPoint(x: imageView.frame.minX + fit.x * scale - bounds.width / 2,
                                y: imageView.frame.minY + fit.y * scale - bounds.height / 2)
            scrollView.contentOffset = CGPoint(x: max(0, min(max(0, scrollView.contentSize.width - bounds.width), point.x)),
                                               y: max(0, min(max(0, scrollView.contentSize.height - bounds.height), point.y)))
        }
        updateOverlay()
    }

    func showOriginal() {
        isMoonFocused = false
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); updateOverlay() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateOverlay() }
    private func centerImage() {
        imageView.center = CGPoint(x: max(scrollView.contentSize.width, bounds.width) / 2,
                                   y: max(scrollView.contentSize.height, bounds.height) / 2)
    }

    @objc private func doubleTapped() {
        guard !isAdjusting else { return }
        if scrollView.zoomScale > scrollView.minimumZoomScale * 1.05 { showOriginal() }
        else { focusOnMoon(animated: true) }
    }

    @objc private func moveAlignment(_ gesture: UIPanGestureRecognizer) {
        let offset = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        onMove?(CGPoint(x: -offset.x / scrollView.zoomScale, y: -offset.y / scrollView.zoomScale))
    }

    private func updateOverlay() {
        guard let fit, let surface else { overlay.update([], selected: nil); return }
        let points: [(MoonAtlasFeature, CGPoint)] = labelsVisible && !isAdjusting ? features.compactMap { feature in
            guard let coordinate = MoonSurfaceCoordinate(latitude: feature.latitude, longitude: feature.longitude),
                  let point = surface.project(coordinate, rotation: fit.rotation),
                  feature.isVisible(moonRadius: fit.radius, emission: point.emissionCosine,
                                    incidence: point.incidenceCosine) else { return nil }
            let x = point.point.x * (fit.mirror == true ? -1 : 1)
            let pixel = CGPoint(x: fit.x + x * fit.radius, y: fit.y + point.point.y * fit.radius)
            let anchor = imageView.convert(pixel, to: overlay)
            return overlay.bounds.insetBy(dx: 4, dy: 4).contains(anchor) ? (feature, anchor) : nil
        } : []
        overlay.update(points, selected: selectedFeatureID)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let center = imageView.convert(CGPoint(x: fit.x, y: fit.y), to: overlay)
        let radius = fit.radius * scrollView.zoomScale
        guide.path = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).cgPath
        CATransaction.commit()
    }
}
