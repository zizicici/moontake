import UIKit

/// A native photo viewer: recognize, zoom to the Moon, then reveal quiet tappable labels.
final class MoonAtlasViewController: UIViewController {
    enum State { case loading, ready, needsAdjustment, failed }
    enum EntrancePhase { case expanding, fullPhoto, focusing, revealing, ready, closed }
    private(set) var recognitionState: State = .loading
    private(set) var entrancePhase: EntrancePhase = .expanding
    let photoView = MoonAtlasPhotoView()
    private let imageInfo: ImageInfo
    private let previewImage: UIImage?
    private let engine = MoonAtlasEngine()
    private var operation: Task<Void, Never>?
    private var entranceTask: Task<Void, Never>?
    private var photo: MoonAtlasPhoto?
    private var result: MoonAtlasResult?
    private var fit: MoonAtlasFit?
    private var date = Date()
    private var adjustmentSnapshot: (fit: MoonAtlasFit, reference: Bool)?
    private let controls = UIStackView()
    private let statusRow = UIStackView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let adjustmentPanel = UIStackView()
    private let rotationSlider = UISlider()
    private let sizeSlider = UISlider()
    private let rotationValue = UILabel()
    private let sizeValue = UILabel()
    private let mirrorSwitch = UISwitch()
    private lazy var referenceButton = tool(String(localized: "atlas.reference"), symbol: "circle.lefthalf.filled", id: "atlas.reference") { [weak self] in
        guard let self else { return }
        self.setReference(!self.photoView.showsReference)
    }
    private lazy var adjustmentButton = tool(String(localized: "atlas.adjust"), symbol: "slider.horizontal.3", id: "atlas.adjust") { [weak self] in
        guard let self else { return }
        if self.adjustmentSnapshot == nil { self.beginAdjustment() }
        else { self.finishAdjustment(accept: true) }
    }

    init(imageInfo: ImageInfo, previewImage: UIImage? = nil) {
        self.imageInfo = imageInfo; self.previewImage = previewImage
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { operation?.cancel(); entranceTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        title = String(localized: "atlas.viewer.title")
        navigationItem.largeTitleDisplayMode = .never
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 15, weight: .medium)]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityLabel = String(localized: "atlas.close")
        navigationController?.navigationBar.tintColor = .white.withAlphaComponent(0.75)
        configureViews()
        photoView.isUserInteractionEnabled = false
        controls.alpha = 0; statusRow.alpha = 0
        if let previewImage { photoView.setPhoto(previewImage) }
        setBusy(true)
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let photo = try await self.engine.load(self.imageInfo)
                guard !Task.isCancelled else { return }
                self.photo = photo
                self.date = photo.captureDate ?? Date()
                if self.entrancePhase != .expanding || self.previewImage == nil { self.photoView.setPhoto(photo.image) }
                await self.recognizePhoto()
            } catch { if !Task.isCancelled { self.showError(error) } }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard entrancePhase == .expanding else { return }
        entrancePhase = .fullPhoto
        if let photo { photoView.setPhoto(photo.image) }
        statusRow.alpha = 1
        if result != nil { presentRecognitionResult() }
        else if recognitionState == .failed { finishEntrance() }
        else { controls.alpha = 1 }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { stopEntrance() }
    }

    private func configureViews() {
        view.addSubview(photoView)
        photoView.translatesAutoresizingMaskIntoConstraints = false
        photoView.onFeature = { [weak self] in self?.showFeature($0) }
        photoView.onMove = { [weak self] translation in
            guard let self, let photo = self.photo, var fit = self.fit, self.adjustmentSnapshot != nil else { return }
            fit.x = min(photo.image.size.width, max(0, fit.x + translation.x))
            fit.y = min(photo.image.size.height, max(0, fit.y + translation.y))
            self.fit = fit
            self.photoView.update(fit: fit, showLabels: false)
            self.photoView.focusOnMoon(animated: false)
        }
        controls.axis = .vertical
        controls.alignment = .fill
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.accessibilityIdentifier = "atlas.status"
        let progress = UIStackView(arrangedSubviews: [spinner, statusLabel])
        progress.alignment = .center
        progress.spacing = 7
        let leading = UIView(), trailing = UIView()
        [leading, progress, trailing].forEach { statusRow.addArrangedSubview($0) }
        leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive = true
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusRow)
        configureAdjustmentPanel()
        controls.addArrangedSubview(adjustmentPanel)
        adjustmentPanel.isHidden = true
        let toolbar = UIStackView(arrangedSubviews: [referenceButton, adjustmentButton])
        toolbar.distribution = .fillEqually
        toolbar.spacing = 12
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        controls.addArrangedSubview(toolbar)
        NSLayoutConstraint.activate([
            statusRow.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            statusRow.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            statusRow.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -10),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            photoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            photoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photoView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -14)
        ])
    }

    private func tool(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        configuration.imagePadding = 6
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var output = input; output.font = .systemFont(ofSize: 13); return output
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.tintColor = .white.withAlphaComponent(0.65)
        button.accessibilityIdentifier = id
        return button
    }

    private func configureAdjustmentPanel() {
        adjustmentPanel.axis = .vertical
        adjustmentPanel.spacing = 6
        adjustmentPanel.accessibilityIdentifier = "atlas.adjustmentPanel"
        rotationSlider.minimumValue = -180; rotationSlider.maximumValue = 180
        sizeSlider.minimumValue = 0.55; sizeSlider.maximumValue = 1.65
        rotationSlider.accessibilityLabel = String(localized: "atlas.rotation")
        sizeSlider.accessibilityLabel = String(localized: "atlas.size")
        for slider in [rotationSlider, sizeSlider] {
            slider.tintColor = .moonColor
            slider.addTarget(self, action: #selector(adjustmentChanged), for: .valueChanged)
        }
        for (title, slider, value) in [(String(localized: "atlas.rotation"), rotationSlider, rotationValue),
                                       (String(localized: "atlas.size"), sizeSlider, sizeValue)] {
            let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabel
            label.widthAnchor.constraint(equalToConstant: 56).isActive = true
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            value.textAlignment = .right; value.textColor = .secondaryLabel
            value.widthAnchor.constraint(equalToConstant: 48).isActive = true
            let row = UIStackView(arrangedSubviews: [label, slider, value]); row.alignment = .center; row.spacing = 8
            row.heightAnchor.constraint(equalToConstant: 36).isActive = true
            adjustmentPanel.addArrangedSubview(row)
        }
        let mirror = UILabel(); mirror.text = String(localized: "atlas.mirror"); mirror.font = .systemFont(ofSize: 12); mirror.textColor = .secondaryLabel
        mirrorSwitch.onTintColor = .moonColor.withAlphaComponent(0.6)
        mirrorSwitch.accessibilityLabel = String(localized: "atlas.mirror")
        mirrorSwitch.addTarget(self, action: #selector(adjustmentChanged), for: .valueChanged)
        let cancel = tool(String(localized: "action.cancel"), symbol: "arrow.uturn.backward", id: "atlas.cancelAdjustment") { [weak self] in self?.finishAdjustment(accept: false) }
        let row = UIStackView(arrangedSubviews: [mirror, mirrorSwitch, UIView(), cancel]); row.alignment = .center; row.spacing = 10
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true
        adjustmentPanel.addArrangedSubview(row)
    }

    private func recognizePhoto() async {
        guard let photo else { return }
        setBusy(true)
        do {
            let result = try await engine.recognize(photo, at: date, mirror: fit?.mirror == true)
            guard !Task.isCancelled else { return }
            self.result = result; fit = result.fit
            if entrancePhase != .expanding { presentRecognitionResult() }
        } catch { if !Task.isCancelled { showError(error) } }
    }

    /// Recognition can finish during the photo transition; visual work waits
    /// for viewDidAppear, then zoom completion, then the last annotation reveal.
    private func presentRecognitionResult() {
        guard let result, entrancePhase != .closed else { return }
        entranceTask?.cancel()
        photoView.cancelEntrance()
        entrancePhase = .fullPhoto
        photoView.setResult(result, showLabels: false)
        photoView.isUserInteractionEnabled = false
        setBusy(false)
        showFitStatus()
        referenceButton.isEnabled = false; adjustmentButton.isEnabled = false
        controls.alpha = 0
        view.layoutIfNeeded()
        entranceTask = Task { [weak self] in
            if !UIAccessibility.isReduceMotionEnabled { try? await Task.sleep(nanoseconds: 120_000_000) }
            guard !Task.isCancelled, let self, self.entrancePhase == .fullPhoto else { return }
            guard result.fit.reason != "disc" else { self.finishEntrance(); return }
            self.entrancePhase = .focusing
            self.photoView.focusForEntrance(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] completed in
                guard let self, completed, self.entrancePhase == .focusing else { return }
                guard result.fit.accepted == true else { self.finishEntrance(); return }
                self.entrancePhase = .revealing
                self.photoView.revealAnnotations(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    guard let self, self.entrancePhase == .revealing else { return }
                    self.finishEntrance()
                }
            }
        }
    }

    private func finishEntrance() {
        guard entrancePhase != .closed else { return }
        entrancePhase = .ready
        photoView.isUserInteractionEnabled = true
        setBusy(false)
        if recognitionState != .failed { showFitStatus() }
        UIView.animate(withDuration: 0.2) { self.controls.alpha = 1; self.statusRow.alpha = 1 }
    }

    private func stopEntrance() {
        entrancePhase = .closed
        operation?.cancel(); entranceTask?.cancel()
        photoView.cancelEntrance()
    }

    private func setBusy(_ busy: Bool) {
        if busy {
            if entrancePhase == .ready { entrancePhase = .fullPhoto }
            photoView.isUserInteractionEnabled = false
            recognitionState = .loading
            spinner.startAnimating()
            setStatus(String(localized: "atlas.recognizing"))
            if let fit { photoView.update(fit: fit, showLabels: false) }
        } else { spinner.stopAnimating() }
        spinner.isHidden = !busy
        referenceButton.isEnabled = !busy && result != nil
        adjustmentButton.isEnabled = !busy && result != nil
        updateMenu(enabled: !busy)
    }

    private func showFitStatus() {
        let accepted = fit?.accepted == true
        recognitionState = accepted ? .ready : .needsAdjustment
        setStatus(accepted ? nil : String(localized: "atlas.needs_adjustment"))
        statusLabel.accessibilityValue = accepted ? "ready" : "needsAdjustment"
        updateMenu(enabled: true)
    }

    private func setStatus(_ message: String?) {
        statusLabel.text = message
        statusRow.isHidden = message?.isEmpty ?? true
    }

    private func showError(_ error: Error) {
        result = nil
        fit?.accepted = false
        if let fit { photoView.update(fit: fit, showLabels: false) }
        setReference(false)
        setBusy(false); recognitionState = .failed
        setStatus(error.localizedDescription)
        statusLabel.accessibilityValue = "failed"
        if entrancePhase != .expanding { finishEntrance() }
    }

    private func setReference(_ visible: Bool) {
        photoView.showsReference = visible
        referenceButton.tintColor = visible ? .moonColor : .white.withAlphaComponent(0.65)
        referenceButton.isSelected = visible
        referenceButton.accessibilityValue = visible ? String(localized: "atlas.visible") : String(localized: "atlas.hidden")
    }

    private func beginAdjustment() {
        guard let fit else { return }
        adjustmentSnapshot = (fit, photoView.showsReference)
        rotationSlider.value = Float((fit.rotation + 540).truncatingRemainder(dividingBy: 360) - 180)
        sizeSlider.value = 1
        mirrorSwitch.isOn = fit.mirror == true
        photoView.isAdjusting = true
        setReference(true)
        setStatus(String(localized: "atlas.drag_to_adjust"))
        adjustmentButton.configuration?.title = String(localized: "atlas.done")
        adjustmentButton.tintColor = .moonColor
        adjustmentPanel.isHidden = false
        updateAdjustmentValues()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        photoView.focusOnMoon(animated: true)
    }

    @objc private func adjustmentChanged() {
        guard let snapshot = adjustmentSnapshot, var fit else { return }
        fit.rotation = Double(rotationSlider.value)
        fit.radius = max(5, snapshot.fit.radius * Double(sizeSlider.value))
        fit.mirror = mirrorSwitch.isOn
        fit.accepted = false
        self.fit = fit
        updateAdjustmentValues()
        photoView.update(fit: fit, showLabels: false)
        photoView.focusOnMoon(animated: false)
    }

    private func updateAdjustmentValues() {
        rotationValue.text = String(format: "%.0f°", rotationSlider.value)
        sizeValue.text = String(format: "%.0f%%", sizeSlider.value * 100)
    }

    private func finishAdjustment(accept: Bool) {
        guard let snapshot = adjustmentSnapshot, var current = fit else { return }
        if accept { current.accepted = true; current.reason = "manual" }
        else { current = snapshot.fit }
        fit = current; adjustmentSnapshot = nil
        photoView.isAdjusting = false
        adjustmentPanel.isHidden = true
        adjustmentButton.configuration?.title = String(localized: "atlas.adjust")
        adjustmentButton.tintColor = .white.withAlphaComponent(0.65)
        setReference(snapshot.reference)
        photoView.update(fit: current, showLabels: current.accepted == true)
        showFitStatus()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func showFeature(_ feature: MoonAtlasFeature) {
        guard presentedViewController == nil else { return }
        photoView.selectedFeatureID = feature.id
        let controller = moonAtlasSheet(MoonAtlasFeatureViewController(feature: feature))
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.selectedDetentIdentifier = .large
        controller.sheetPresentationController?.prefersGrabberVisible = true
        controller.sheetPresentationController?.preferredCornerRadius = 24
        present(controller, animated: true)
    }

    private func updateMenu(enabled: Bool) {
        let original = UIAction(title: String(localized: "atlas.original"), image: UIImage(systemName: "arrow.down.right.and.arrow.up.left"), identifier: UIAction.Identifier("atlas.original")) { [weak self] _ in self?.photoView.showOriginal() }
        let retry = UIAction(title: String(localized: "atlas.retry"), image: UIImage(systemName: "arrow.clockwise"), identifier: UIAction.Identifier("atlas.retry")) { [weak self] _ in
            guard let self else { return }
            self.finishAdjustment(accept: false)
            self.operation?.cancel()
            self.operation = Task { await self.recognizePhoto() }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [original, retry]))
        navigationItem.rightBarButtonItem?.isEnabled = enabled && photo != nil && entrancePhase == .ready
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "atlas.more")
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "atlas.more"
    }

    @objc private func close() { stopEntrance(); dismiss(animated: true) }
}
