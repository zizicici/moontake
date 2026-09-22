import UIKit
import SnapKit
import SkyKit

/// A transparent HUD over the existing camera. Only the Settings button consumes touches.
final class MoonFinderView: UIView {
    var settingsAction: (() -> Void)?
    var cameraGeometry: (() -> (imageRect: CGRect, fieldOfView: Double, zoom: Double)?)?
    private var state = MoonFinderState(status: .locating)
    private let statusPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let coordinatesLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let targetRing = UIView()
    private let targetLabel = UILabel()
    private let edgeArrow = UIImageView(image: UIImage(systemName: "arrow.up",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "moonFinder.panel"
        clipsToBounds = true
        statusPanel.layer.cornerRadius = 16
        statusPanel.clipsToBounds = true
        addSubview(statusPanel)
        statusPanel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.width.lessThanOrEqualTo(380)
            $0.left.greaterThanOrEqualToSuperview().inset(12)
            $0.right.lessThanOrEqualToSuperview().inset(12)
            $0.width.equalToSuperview().offset(-24).priority(.high)
            $0.bottom.equalToSuperview().inset(56)
        }
        symbolView.tintColor = .moonColor
        symbolView.contentMode = .scaleAspectFit
        symbolView.snp.makeConstraints { $0.size.equalTo(20) }
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        coordinatesLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        for label in [titleLabel, detailLabel, coordinatesLabel] {
            label.textColor = .moonColor
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        detailLabel.textColor = .moonColor.withAlphaComponent(0.85)
        titleLabel.accessibilityIdentifier = "moonFinder.status"
        coordinatesLabel.accessibilityIdentifier = "moonFinder.coordinates"
        settingsButton.setTitle(String(localized: "moon_finder.settings"), for: .normal)
        settingsButton.tintColor = .moonColor
        settingsButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        settingsButton.accessibilityIdentifier = "moonFinder.settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        settingsButton.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
        let heading = UIStackView(arrangedSubviews: [symbolView, titleLabel])
        heading.spacing = 8
        heading.alignment = .center
        let stack = UIStackView(arrangedSubviews: [heading, coordinatesLabel, detailLabel, settingsButton])
        stack.axis = .vertical
        stack.spacing = 6
        statusPanel.contentView.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(12) }

        // A hollow ring leaves the real Moon visible through its center.
        targetRing.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        targetRing.layer.cornerRadius = 24
        targetRing.layer.borderWidth = 2
        targetRing.layer.shadowColor = UIColor.black.cgColor
        targetRing.layer.shadowOpacity = 0.8
        targetRing.layer.shadowRadius = 4
        targetRing.layer.shadowOffset = .zero
        targetRing.accessibilityIdentifier = "moonFinder.target"
        targetRing.isAccessibilityElement = true
        targetRing.accessibilityLabel = String(localized: "moon_finder.target")
        addSubview(targetRing)
        targetLabel.text = String(localized: "moon_finder.target")
        targetLabel.textColor = .moonColor
        targetLabel.font = .preferredFont(forTextStyle: .caption1)
        targetLabel.textAlignment = .center
        targetLabel.backgroundColor = .black.withAlphaComponent(0.55)
        targetLabel.layer.cornerRadius = 6
        targetLabel.clipsToBounds = true
        targetLabel.isAccessibilityElement = false
        addSubview(targetLabel)
        edgeArrow.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        edgeArrow.contentMode = .center
        edgeArrow.tintColor = .moonColor
        edgeArrow.backgroundColor = .black.withAlphaComponent(0.55)
        edgeArrow.layer.cornerRadius = 22
        edgeArrow.accessibilityIdentifier = "moonFinder.arrow"
        addSubview(edgeArrow)
        update(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, !settingsButton.isHidden else { return nil }
        return settingsButton.hitTest(settingsButton.convert(point, from: self), with: event)
    }

    @objc private func openSettings() { settingsAction?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTarget()
    }

    func update(_ state: MoonFinderState) {
        self.state = state
        settingsButton.isHidden = state.status != .locationDenied
        coordinatesLabel.isHidden = state.position == nil
        if let position = state.position {
            coordinatesLabel.text = String.localizedStringWithFormat(
                String(localized: "moon_finder.coordinates"), position.azimuth, position.altitude)
        }
        let key: String
        let symbol: String
        switch state.status {
        case .ephemerisUnavailable: (key, symbol) = ("ephemeris_error", "moon")
        case .locating: (key, symbol) = ("locating", "location")
        case .locationDenied: (key, symbol) = ("permission", "location.slash")
        case .locationUnavailable: (key, symbol) = ("location_error", "location.slash")
        case .sensorsUnavailable: (key, symbol) = ("sensors", "safari")
        case .calibrating: (key, symbol) = ("calibrating", "iphone.radiowaves.left.and.right")
        case .belowHorizon: (key, symbol) = ("below_horizon", "moon.zzz")
        case .tracking: (key, symbol) = ("tracking", "viewfinder")
        }
        titleLabel.text = NSLocalizedString("moon_finder.\(key).title", comment: "")
        detailLabel.text = NSLocalizedString("moon_finder.\(key).detail", comment: "")
        symbolView.image = UIImage(systemName: symbol)
        updateTarget()
        setNeedsLayout()
    }

    private func updateTarget() {
        targetRing.isHidden = true
        targetLabel.isHidden = true
        edgeArrow.isHidden = true
        guard state.status == .tracking, let guidance = state.guidance else { return }
        titleLabel.text = String(localized: guidance.isBehindCamera
            ? "moon_finder.turn_around.title" : "moon_finder.tracking.title")
        detailLabel.text = String.localizedStringWithFormat(
            String(localized: "moon_finder.tracking.detail"), guidance.angularDistance)
        guard let geometry = cameraGeometry?() else { return }
        // Reserve space for the top-left toggle, the bottom status and marker labels.
        let imageBounds = geometry.imageRect.intersection(bounds)
        let safeBounds = CGRect(x: imageBounds.minX + 32, y: max(imageBounds.minY + 32, 104),
                                width: imageBounds.width - 64,
                                height: min(imageBounds.maxY - 32, bounds.maxY - 106 - max(120, statusPanel.bounds.height))
                                    - max(imageBounds.minY + 32, 104))
        guard let projection = MoonProjection.project(guidance, imageRect: geometry.imageRect,
            horizontalFieldOfView: geometry.fieldOfView, zoom: geometry.zoom, markerBounds: safeBounds) else { return }
        if projection.isOnScreen {
            targetRing.isHidden = false
            targetLabel.isHidden = false
            targetRing.center = projection.point
            let centered = hypot(projection.point.x - geometry.imageRect.midX,
                                 projection.point.y - geometry.imageRect.midY) <= 24
            targetRing.layer.borderColor = (centered ? UIColor.systemGreen : .moonColor).cgColor
            let labelSize = targetLabel.sizeThatFits(CGSize(width: bounds.width - 24, height: 50))
            let labelWidth = min(bounds.width - 24, labelSize.width + 16)
            targetLabel.frame = CGRect(x: min(max(12, projection.point.x - labelWidth / 2), bounds.width - 12 - labelWidth),
                                       y: projection.point.y + 30, width: labelWidth, height: labelSize.height + 8)
            titleLabel.text = String(localized: "moon_finder.aligned.title")
            detailLabel.text = String(localized: "moon_finder.aligned.detail")
        } else {
            edgeArrow.isHidden = false
            edgeArrow.center = projection.point
            edgeArrow.transform = CGAffineTransform(rotationAngle: projection.arrowRotation)
        }
    }
}
