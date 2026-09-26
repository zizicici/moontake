import UIKit

final class MoonAtlasLabelsView: UIView {
    private final class Annotation {
        let button = UIButton(type: .custom)
        let line = CAShapeLayer()
        let dot = CAShapeLayer()

        init() {
            line.strokeColor = UIColor.white.withAlphaComponent(0.38).cgColor
            line.fillColor = UIColor.clear.cgColor
            line.lineWidth = 0.75
            dot.fillColor = UIColor.moonColor.withAlphaComponent(0.85).cgColor
        }

        func setVisible(_ visible: Bool) {
            button.alpha = visible ? 1 : 0
            button.isUserInteractionEnabled = visible
            CATransaction.begin(); CATransaction.setDisableActions(true)
            line.opacity = visible ? 1 : 0; dot.opacity = visible ? 1 : 0
            CATransaction.commit()
        }
    }

    private var annotations: [String: Annotation] = [:]
    private var features: [String: MoonAtlasFeature] = [:]
    private var orderedIDs: [String] = []
    private var revealWork: [DispatchWorkItem] = []
    private var revealGeneration = 0
    private var revealing = false
    private var revealedIDs: Set<String> = []
    var onFeature: ((MoonAtlasFeature) -> Void)?
    var visibleAnnotationCount: Int {
        annotations.values.filter { !$0.button.isHidden && $0.button.alpha > 0 }.count
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func prepareReveal() {
        cancelReveal()
        revealing = true
        revealedIDs = []
        annotations.values.forEach { $0.setVisible(false) }
    }

    func reveal(animated: Bool, completion: @escaping () -> Void) {
        let generation = revealGeneration
        guard animated, !orderedIDs.isEmpty else {
            revealing = false
            annotations.values.forEach { $0.setVisible(true) }
            completion(); return
        }
        for (index, id) in orderedIDs.enumerated() {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.revealGeneration == generation, let annotation = self.annotations[id] else { return }
                self.revealedIDs.insert(id)
                UIView.animate(withDuration: 0.22) { annotation.button.alpha = 1 }
                annotation.button.isUserInteractionEnabled = true
                CATransaction.begin(); CATransaction.setDisableActions(true)
                annotation.line.opacity = 1; annotation.dot.opacity = 1
                CATransaction.commit()
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.22
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.22
                annotation.line.add(draw, forKey: "draw")
                annotation.line.add(fade, forKey: "appear")
                annotation.dot.add(fade, forKey: "appear")
            }
            revealWork.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.065, execute: work)
        }
        let finish = DispatchWorkItem { [weak self] in
            guard let self, self.revealGeneration == generation else { return }
            self.revealing = false
            self.revealWork = []
            self.annotations.values.forEach { $0.setVisible(true) }
            completion()
        }
        revealWork.append(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(orderedIDs.count - 1) * 0.065 + 0.22, execute: finish)
    }

    func cancelReveal() {
        revealGeneration += 1
        revealWork.forEach { $0.cancel() }; revealWork = []
        revealing = false
        annotations.values.forEach {
            $0.button.layer.removeAllAnimations(); $0.line.removeAllAnimations(); $0.dot.removeAllAnimations()
        }
    }

    func update(_ points: [(MoonAtlasFeature, CGPoint)], selected: String?) {
        annotations.values.forEach { $0.button.isHidden = true; $0.line.isHidden = true; $0.dot.isHidden = true }
        let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let width: CGFloat = chinese ? 62 : min(116, bounds.width * 0.29)
        // Lay out the entire set before revealing any annotation. Introducing
        // names one at a time must not move names that are already on screen.
        let placements = MoonAtlasLabelLayout.arrange(points.map { $0.1 }, in: bounds, labelSize: CGSize(width: width, height: 44))
        orderedIDs = placements.sorted {
            $0.frame.midY == $1.frame.midY ? $0.frame.midX < $1.frame.midX : $0.frame.midY < $1.frame.midY
        }.map { points[$0.index].0.id }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for placement in placements {
            let (feature, anchor) = points[placement.index]
            let annotation: Annotation
            if let existing = annotations[feature.id] { annotation = existing }
            else {
                annotation = Annotation()
                let button = annotation.button
                button.titleLabel?.font = .systemFont(ofSize: chinese ? 13 : 11, weight: .medium)
                button.titleLabel?.numberOfLines = 2
                button.titleLabel?.textAlignment = .center
                button.setTitle(feature.labelName, for: .normal)
                button.accessibilityLabel = feature.displayName
                button.accessibilityIdentifier = "atlas.feature.\(feature.id)"
                button.layer.cornerRadius = 9
                button.addAction(UIAction { [weak self] _ in
                    guard let self, let value = self.features[feature.id] else { return }
                    self.onFeature?(value)
                }, for: .touchUpInside)
                annotations[feature.id] = annotation
                layer.insertSublayer(annotation.line, at: 0); layer.insertSublayer(annotation.dot, at: 1)
                addSubview(button)
                annotation.setVisible(!revealing || revealedIDs.contains(feature.id))
            }
            features[feature.id] = feature
            annotation.button.isHidden = false; annotation.line.isHidden = false; annotation.dot.isHidden = false
            annotation.button.setTitleColor(feature.id == selected ? .moonColor : .white.withAlphaComponent(0.9), for: .normal)
            annotation.button.backgroundColor = UIColor.black.withAlphaComponent(feature.id == selected ? 0.64 : 0.38)
            annotation.button.frame = placement.frame
            if !revealing { annotation.setVisible(true) }
            let path = UIBezierPath(); path.move(to: anchor); path.addLine(to: placement.endpoint)
            annotation.line.path = path.cgPath
            annotation.dot.path = UIBezierPath(ovalIn: CGRect(x: anchor.x - 2, y: anchor.y - 2, width: 4, height: 4)).cgPath
        }
        CATransaction.commit()
    }
}
