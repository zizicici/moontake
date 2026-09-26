import UIKit
import SafariServices

/// Opaque reading surface in the same palette as the album. Set the container's
/// traits as well so system sheet chrome does not inherit a light appearance.
func moonAtlasSheet(_ root: UIViewController) -> UINavigationController {
    let navigation = UINavigationController(rootViewController: root)
    navigation.overrideUserInterfaceStyle = .dark
    navigation.view.backgroundColor = .skyColor
    navigation.navigationBar.tintColor = .moonColor
    let appearance = UINavigationBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = .skyColor
    appearance.shadowColor = .clear
    appearance.titleTextAttributes = [.foregroundColor: UIColor.moonColor]
    navigation.navigationBar.standardAppearance = appearance
    navigation.navigationBar.scrollEdgeAppearance = appearance
    navigation.navigationBar.compactAppearance = appearance
    return navigation
}

final class MoonAtlasFeatureViewController: UIViewController {
    let feature: MoonAtlasFeature
    init(feature: MoonAtlasFeature) { self.feature = feature; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .skyColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        let name = label(feature.displayName, style: .title2, color: .moonColor)
        name.accessibilityTraits.insert(.header)
        name.accessibilityIdentifier = "atlas.featureName"
        stack.addArrangedSubview(name)
        if feature.displayName != feature.name {
            stack.setCustomSpacing(6, after: name)
            stack.addArrangedSubview(label(feature.name, style: .footnote))
        }
        addSection(.naming, title: String(localized: "atlas.article.naming"), to: stack)
        if let reference = feature.reference,
           let url = Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources/assets/details/\(feature.id).jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .black
            imageView.layer.cornerRadius = 8
            imageView.clipsToBounds = true
            imageView.isAccessibilityElement = true
            imageView.accessibilityIdentifier = "atlas.featureReference"
            imageView.accessibilityLabel = String(format: String(localized: "atlas.feature_reference.accessibility"), feature.displayName)
            stack.addArrangedSubview(imageView)
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 2.0 / 3.0).isActive = true
            stack.setCustomSpacing(8, after: imageView)

            let caption = UIStackView(arrangedSubviews: [label(String(localized: "atlas.feature_reference"), style: .caption1),
                                                       label(String(localized: "atlas.north_up"), style: .caption1)])
            caption.axis = .horizontal; caption.distribution = .equalSpacing; caption.spacing = 12
            stack.addArrangedSubview(caption)
            stack.setCustomSpacing(0, after: caption)
            let credit = UIButton(type: .system)
            credit.setTitle(reference.credit, for: .normal)
            credit.tintColor = .moonColor.withAlphaComponent(0.65)
            credit.contentHorizontalAlignment = .leading
            credit.titleLabel?.font = .preferredFont(forTextStyle: .caption2)
            credit.titleLabel?.adjustsFontForContentSizeCategory = true
            credit.titleLabel?.numberOfLines = 0
            credit.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            credit.accessibilityIdentifier = "atlas.featureReferenceSource"
            credit.addTarget(self, action: #selector(openImageSource), for: .touchUpInside)
            stack.addArrangedSubview(credit)
            stack.setCustomSpacing(8, after: credit)
        }
        addSection(.story, title: String(localized: "atlas.article.story"), to: stack)
        addSection(.observation, title: String(localized: "atlas.article.observation"), to: stack)
        let statistics = UIStackView(); statistics.axis = .horizontal; statistics.distribution = .fillEqually; statistics.spacing = 14
        let sizeTitle = feature.type == "mountain" ? String(localized: "atlas.extent") : String(localized: "atlas.diameter")
        for (title, value) in [(sizeTitle, "≈ \(Int(feature.diameterKm.rounded()).formatted()) km"),
                               (String(localized: "atlas.coordinates"), feature.coordinateText)] {
            let column = UIStackView(arrangedSubviews: [label(title, style: .caption1), label(value, style: .subheadline, color: .moonColor)])
            column.axis = .vertical; column.spacing = 6; statistics.addArrangedSubview(column)
        }
        stack.addArrangedSubview(statistics)
        stack.addArrangedSubview(label(String(localized: "atlas.point_note"), style: .footnote))
        let source = UIButton(type: .system)
        source.setTitle(String(localized: "atlas.article.sources"), for: .normal)
        source.tintColor = .moonColor
        source.contentHorizontalAlignment = .leading
        source.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        source.titleLabel?.adjustsFontForContentSizeCategory = true
        source.titleLabel?.numberOfLines = 0
        source.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        source.accessibilityIdentifier = "atlas.articleSources"
        let record = UIAction(title: String(localized: "atlas.source")) { [weak self] _ in
            guard let self else { return }
            self.openReadingSource(self.feature.source)
        }
        let reading = feature.readingSources.map { reference in
            UIAction(title: reference.displayTitle) { [weak self] _ in self?.openReadingSource(reference.url) }
        }
        source.menu = UIMenu(children: reading + [record])
        source.showsMenuAsPrimaryAction = true
        stack.addArrangedSubview(source)
    }

    private func addSection(_ section: MoonAtlasArticleSection, title: String, to stack: UIStackView) {
        let heading = label(title, style: .footnote)
        heading.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(7, after: heading)
        let body = label(feature.articleText(section), style: .subheadline, color: .moonColor)
        body.accessibilityIdentifier = "atlas.article.\(section.rawValue)"
        stack.addArrangedSubview(body)
    }

    private func label(_ text: String, style: UIFont.TextStyle, color: UIColor = .moonColor.withAlphaComponent(0.75)) -> UILabel {
        let label = UILabel(); label.numberOfLines = 0; label.textColor = color
        label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        label.attributedText = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
        return label
    }
    @objc private func close() { dismiss(animated: true) }
    private func openReadingSource(_ url: URL) {
        // Only curated, bundled references can be opened from the reading menu.
        guard url.scheme == "https", url.host != nil,
              url == feature.source || feature.readingSources.contains(where: { $0.url == url }) else { return }
        present(SFSafariViewController(url: url), animated: true)
    }
    @objc private func openImageSource() {
        guard let source = feature.reference?.source, source.scheme == "https",
              ["svs.gsfc.nasa.gov", "data.lroc.im-ldi.com"].contains(source.host ?? "") else { return }
        present(SFSafariViewController(url: source), animated: true)
    }
}
