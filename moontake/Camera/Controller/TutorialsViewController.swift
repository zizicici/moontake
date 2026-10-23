import UIKit
import TipKit

/// Coordinates system tips over the existing camera. Only the current step's
/// controls receive touches through the popover; using them advances the guide.
final class TutorialsViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    var targetRects: ((CameraTutorialStep, UIView) -> [CGRect])?
    var interactionViews: ((CameraTutorialStep) -> [UIView])?
    var onFinish: (() -> Void)?
    var onShowStep: ((CameraTutorialStep) -> Void)?
    private(set) var stepIndex = 0
    private(set) var popoverController: UIViewController?
    let steps: [CameraTutorialStep]
    let isTip: Bool
    var currentStep: CameraTutorialStep { steps[stepIndex] }

    private let anchor = UIView()
    private let presentationID = UUID().uuidString
    private var observation: Task<Void, Never>?
    private var transitioning = false
    private var finished = false

    init(steps: [CameraTutorialStep] = CameraTutorialStep.basics, isTip: Bool = false) {
        precondition(!steps.isEmpty)
        self.steps = steps
        self.isTip = isTip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        steps = CameraTutorialStep.basics
        isTip = false
        super.init(coder: coder)
    }

    deinit { observation?.cancel() }

    override func loadView() { view = TutorialPassthroughView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "tutorial.camera"
        anchor.isUserInteractionEnabled = false
        anchor.accessibilityElementsHidden = true
        view.addSubview(anchor)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showStepIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let targets = targetRects?(currentStep, view) ?? []
        // Brightness has two buttons; point to +, rather than the shutter between them.
        anchor.frame = (targets.last ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1))
            .intersection(view.bounds)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { observation?.cancel() }
    }

    @available(iOS 17.0, *)
    var currentTip: CameraControlTip {
        CameraControlTip(id: presentationID + "." + currentStep.rawValue,
                         step: currentStep)
    }

    private func showStepIfNeeded() {
        guard !finished, !transitioning, observation == nil, popoverController == nil,
              viewIfLoaded?.window != nil else { return }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if #available(iOS 17.0, *), CameraControlTip.isConfigured {
            let tip = currentTip
            observation = Task { @MainActor [weak self] in
                for await status in tip.statusUpdates {
                    guard !Task.isCancelled, let self else { return }
                    switch status {
                    case .available:
                        guard self.popoverController == nil else { continue }
                        let popover = TipUIPopoverViewController(tip, sourceItem: self.anchor)
                        popover.imageSize = CGSize(width: 24, height: 24)
                        if #available(iOS 18.0, *) {
                            popover.imageStyle = Color(uiColor: .skyColor)
                        }
                        popover.presentationDelegate = self
                        self.show(popover)
                    case .invalidated:
                        // The system close button invalidates its tip.
                        self.finish()
                        return
                    case .pending:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        } else {
            let popover = LegacyCameraTipController(step: currentStep)
            popover.onClose = { [weak self] in self?.finish() }
            popover.modalPresentationStyle = .popover
            popover.popoverPresentationController?.sourceView = anchor
            popover.popoverPresentationController?.sourceRect = anchor.bounds
            popover.popoverPresentationController?.delegate = self
            show(popover)
        }
    }

    private func show(_ popover: UIViewController) {
        popoverController = popover
        popover.view.accessibilityIdentifier = "tutorial.tip"
        popover.view.accessibilityViewIsModal = isTip
        popover.popoverPresentationController?.passthroughViews = isTip ? [] : interactionViews?(currentStep)
        popover.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        present(popover, animated: true) { [weak self] in
            guard let self, !self.finished else { return }
            self.onShowStep?(self.currentStep)
        }
    }

    func didPerform(_ step: CameraTutorialStep) {
        guard !isTip, step == currentStep, popoverController != nil else { return }
        if step == .capture {
            // Clear the presentation before capture can report an error or save alert.
            finish(animated: false)
        } else {
            advance()
        }
    }

    private func advance() {
        guard !finished, !transitioning else { return }
        guard stepIndex < steps.count - 1 else { finish(); return }
        transitioning = true
        observation?.cancel()
        observation = nil
        dismissTip { [weak self] in
            guard let self else { return }
            self.stepIndex += 1
            self.transitioning = false
            self.showStepIfNeeded()
        }
    }

    func finish(animated: Bool = true) {
        guard !finished, !transitioning else { return }
        finished = true
        observation?.cancel()
        observation = nil
        dismissTip(animated: animated) { [weak self] in self?.onFinish?() }
    }

    private func dismissTip(animated: Bool = true, completion: @escaping () -> Void) {
        guard let popover = popoverController else { completion(); return }
        popoverController = nil
        if popover.presentingViewController != nil {
            popover.dismiss(animated: animated, completion: completion)
        } else {
            completion()
        }
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        finish()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    override func accessibilityPerformEscape() -> Bool {
        finish()
        return true
    }
}

private final class TutorialPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

/// iOS 15–16 fallback. Modern systems use the native TipKit presentation above.
private final class LegacyCameraTipController: UIViewController {
    var onClose: (() -> Void)?
    private let step: CameraTutorialStep
    private let stack = UIStackView()

    init(step: CameraTutorialStep) {
        self.step = step
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        let label = UILabel()
        label.text = step.instruction
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        let close = UIButton(type: .close)
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)
        let icon = UIImageView(image: UIImage(systemName: step.symbolName))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        icon.tintColor = .skyColor
        icon.adjustsImageSizeForAccessibilityContentSizeCategory = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        let header = UIStackView(arrangedSubviews: [icon, label, close])
        header.alignment = .top
        header.spacing = 12
        stack.axis = .vertical
        stack.addArrangedSubview(header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
        let width = min(320, presentingViewController?.view.bounds.width ?? 320) - 32
        let size = stack.systemLayoutSizeFitting(CGSize(width: width - 32, height: 0),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        preferredContentSize = CGSize(width: width, height: size.height + 32)
    }
}
