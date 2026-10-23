import UIKit
import MoreKit

extension UIColor {
    static let paywallAccent = UIColor { $0.userInterfaceStyle == .dark ? .moonColor : .skyColor }
}

enum MoontakePaywallPalette {
    static let card = UIColor { $0.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.07) : .white.withAlphaComponent(0.8) }
    static let selectedCard = UIColor.paywallAccent.withAlphaComponent(0.13)
    static let tableRow = UIColor.secondarySystemGroupedBackground
    static let freeColumn = UIColor.paywallAccent.withAlphaComponent(0.04)
    static let proColumn = UIColor.paywallAccent.withAlphaComponent(0.10)
}

final class MoontakePaywallBackground: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        gradient.colors = (dark
            ? [UIColor(red: 0.10, green: 0.09, blue: 0.22, alpha: 1), UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)]
            : [UIColor(red: 0.92, green: 0.91, blue: 0.99, alpha: 1), UIColor(red: 0.99, green: 0.97, blue: 0.90, alpha: 1)]).map(\.cgColor)
    }
}

// Shared branding keeps Pro separate from the app name at both entry points.
final class MoontakeProTitleView: UIView {
    private let name = UILabel()
    private let badge = UILabel()
    private let badgeBackground = UIView()
    private let badgeStyle: MoreBadgeStyle?
    private let stack = UIStackView()
    private let pointSize: CGFloat
    private let weight: UIFont.Weight
    private let textStyle: UIFont.TextStyle

    init(pointSize: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle, color: UIColor = .label,
         badgeStyle: MoreBadgeStyle? = nil) {
        self.pointSize = pointSize
        self.weight = weight
        self.textStyle = textStyle
        self.badgeStyle = badgeStyle
        super.init(frame: .zero)
        name.text = "moontake"
        name.textColor = color
        name.adjustsFontForContentSizeCategory = true
        badge.text = badgeStyle?.text ?? "Pro"
        badge.textColor = badgeStyle?.textColor ?? .skyColor
        badge.adjustsFontForContentSizeCategory = true
        badgeBackground.backgroundColor = badgeStyle?.backgroundColor ?? .moonColor
        badgeBackground.layer.cornerCurve = badgeStyle == nil ? .continuous : .circular
        badgeBackground.insetsLayoutMarginsFromSafeArea = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: badgeBackground.layoutMarginsGuide.leadingAnchor),
            badge.trailingAnchor.constraint(equalTo: badgeBackground.layoutMarginsGuide.trailingAnchor),
            badge.topAnchor.constraint(equalTo: badgeBackground.layoutMarginsGuide.topAnchor),
            badge.bottomAnchor.constraint(equalTo: badgeBackground.layoutMarginsGuide.bottomAnchor)
        ])
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(badgeBackground)
        stack.alignment = .center
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityLabel = MoontakeProBenefits.title
        accessibilityTraits = .header
        accessibilityIdentifier = "pro.title"
        updateTypography()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTypography()
    }

    private func updateTypography() {
        name.font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: .systemFont(ofSize: pointSize, weight: weight), compatibleWith: traitCollection)
        if let style = badgeStyle {
            // Match MoreKit's settings badges, including Dynamic Type scaling.
            let metrics = UIFontMetrics(forTextStyle: .caption2)
            badge.font = metrics.scaledFont(for: style.font, compatibleWith: traitCollection)
            func scaled(_ value: CGFloat) -> CGFloat { metrics.scaledValue(for: value, compatibleWith: traitCollection) }
            badgeBackground.directionalLayoutMargins = .init(top: scaled(style.contentInsets.top),
                leading: scaled(style.contentInsets.left), bottom: scaled(style.contentInsets.bottom),
                trailing: scaled(style.contentInsets.right))
            badgeBackground.layer.cornerRadius = scaled(style.cornerRadius)
        } else {
            badge.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: pointSize >= 30 ? 15 : 12, weight: .bold), compatibleWith: traitCollection)
            badgeBackground.directionalLayoutMargins = .init(top: 3, leading: 8, bottom: 3, trailing: 8)
            badgeBackground.layer.cornerRadius = 6
        }
        invalidateIntrinsicContentSize()
    }
}

final class MoontakePaywallHeader: UIView {
    private let heading = MoontakeProTitleView(pointSize: 32, weight: .semibold, textStyle: .largeTitle)
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let artwork = MoontakeProArtwork()
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 16))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [heading, subtitleLabel])
        text.axis = .vertical
        text.spacing = 10
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            artwork.centerXAnchor.constraint(equalTo: centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 160),
            artwork.heightAnchor.constraint(equalToConstant: 160),
            text.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 32),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            text.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(subtitle: String) { subtitleLabel.text = subtitle }
}

private final class MoontakeProArtwork: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        let icon = UIImageView(image: AppInfo.App.moontake.image)
        icon.accessibilityIdentifier = "paywall.appIcon"
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 26
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        let crown = MoontakeProCrownView()
        for child in [icon, crown] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            icon.widthAnchor.constraint(equalToConstant: 112),
            icon.heightAnchor.constraint(equalToConstant: 112),
            crown.centerXAnchor.constraint(equalTo: icon.trailingAnchor, constant: -4),
            crown.centerYAnchor.constraint(equalTo: icon.topAnchor, constant: 2),
            crown.widthAnchor.constraint(equalToConstant: 48),
            crown.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
