//
//  CameraViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//

import AVKit
import Photos
import SnapKit
import UIKit
import CoreMotion
import Toast

struct CustomSettings {
    static var shared: CustomSettings = CustomSettings()
    
    var locationName: String?
}

private func exposureButtonFont(for title: String) -> UIFont {
    let baseSize: CGFloat = 12
    let baseFont = UIFont.systemFont(ofSize: baseSize)
    let measuredWidth = (title as NSString).size(withAttributes: [.font: baseFont]).width
    // Fit longer translations inside the exposure controls.
    return UIFont.systemFont(ofSize: min(baseSize, baseSize * 42 / max(measuredWidth, 1)))
}

class CameraViewController: UIViewController {
    private let tutorialProgress: CameraTutorialProgress
    private let moonSharePrompt: MonthlyMoonSharePrompt
    private var tutorialController: TutorialsViewController?
    private var tutorialRequested = false
    private var hasPresentedAutomaticGuide = false
    private var isCameraVisible = false
    private var tutorialAccessibility: [(UIView, Bool)] = []
    private var tutorialFocusSliderMoved = false

    init(tutorialProgress: CameraTutorialProgress = CameraTutorialProgress(), moonSharePrompt: MonthlyMoonSharePrompt? = nil) {
        self.tutorialProgress = tutorialProgress
        self.moonSharePrompt = moonSharePrompt ?? MonthlyMoonSharePrompt()
        super.init(nibName: nil, bundle: nil)
        self.moonSharePrompt.onReady = { [weak self] in self?.showPendingTemporaryPhoto() }
    }

    required init?(coder: NSCoder) {
        tutorialProgress = CameraTutorialProgress()
        moonSharePrompt = MonthlyMoonSharePrompt()
        super.init(coder: coder)
        moonSharePrompt.onReady = { [weak self] in self?.showPendingTemporaryPhoto() }
    }

    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "capture")
    
    private var captureDevice: AVCaptureDevice?
    private var captureDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    
    private var liveAudioInput: AVCaptureDeviceInput? // sessionQueue only
    private var pendingTemporaryPhoto: CapturedPhoto?
    private var livePhotoEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhoto.rawValue)
    private var livePhotoAudioEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhotoAudio.rawValue)
    private var livePhotoSupported = false
    private var liveAudioActive = false
    private var livePhotoConfiguring = false
    private var captureBusy = false
    private var sessionReady = false
    private var liveRecording = false
    private var liveSupportObservation: NSKeyValueObservation?
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var isProcessing: Bool = false {
        didSet {
            albumButton.setNeedsUpdateConfiguration()
        }
    }
    
    private var spinner: UIActivityIndicatorView!
    private let previewView: AVCaptureVideoPreviewView = AVCaptureVideoPreviewView()
    private let moonFinder = MoonFinderManager()
    private let moonFinderView = MoonFinderView()
    private let moonCalendarButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "calendar")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.alpha = 0.75
        button.accessibilityLabel = String(localized: "moon_calendar.title")
        button.accessibilityIdentifier = "moonCalendar.open"
        return button
    }()
    private let moonFinderButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "moon.stars")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.alpha = 0.75
        button.accessibilityLabel = String(localized: "moon_finder.open")
        button.accessibilityIdentifier = "moonFinder.toggle"
        return button
    }()
    private let captureButton : UIButton = {
        let button = ColorHighlightButton()
        button.normalColor = .moonColor
        button.highlightedColor = .moonColor.withAlphaComponent(0.6)
        button.layer.cornerRadius = 32
        button.layer.shadowColor = UIColor.moonColor.cgColor
        button.layer.shadowOpacity = 1.0
        button.layer.shadowOffset = CGSize(width: 0, height: 0)
        button.layer.shadowRadius = 10.0
        button.layer.masksToBounds = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "camera.capture.a11y")
        button.accessibilityIdentifier = "camera.capture"

        return button
    }()
    private let informationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        label.textAlignment = .center
        label.textColor = .moonColor.withAlphaComponent(0.75)
        label.numberOfLines = 1
        label.minimumScaleFactor = 0.5
        label.adjustsFontSizeToFitWidth = true
        
        return label
    }()
    private let plusButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePlacement = .top
        configuration.imagePadding = 10.0
        configuration.titleLineBreakMode = .byClipping
        let title = String(localized: "camera.exposure.increase.title")
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = exposureButtonFont(for: title)

            return outgoing
        })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 8, trailing: 4)
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "camera.exposure.increase.a11y")
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.titleLabel?.lineBreakMode = .byClipping
        
        return button
    }()
    private let minusButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "minus")
        configuration.imagePlacement = .top
        configuration.imagePadding = 10.0
        configuration.titleLineBreakMode = .byClipping
        let title = String(localized: "camera.exposure.decrease.title")
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = exposureButtonFont(for: title)

            return outgoing
        })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 8, trailing: 4)

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "camera.exposure.decrease.a11y")
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.titleLabel?.lineBreakMode = .byClipping
        
        return button
    }()
    private let lensPositionSlider: UISlider = {
        var slider = UISlider()
        slider.minimumTrackTintColor = .moonColor.withAlphaComponent(0.83)
        slider.accessibilityLabel = String(localized: "camera.focus.title")
        slider.accessibilityIdentifier = "camera.focus"

        return slider
    }()
    private let sliderLabel: UILabel = {
        var label = UILabel()
        label.text = String(localized: "camera.focus.title")
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .moonColor.withAlphaComponent(0.75)
        label.isUserInteractionEnabled = false
        
        return label
    }()
    private let albumButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "photo.on.rectangle")

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "album.title")
        button.accessibilityIdentifier = "camera.album"
        
        return button
    }()
    private let locationButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "mappin.slash")
        configuration.contentInsets = .zero
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "location.title")
        button.accessibilityIdentifier = "camera.location"
        button.alpha = 0.65
        button.showsMenuAsPrimaryAction = true
        
        return button
    }()
    private let locationNameButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityIdentifier = "camera.locationName"
        button.accessibilityHint = String(localized: "location.custom.intro")
        button.isHidden = true
        return button
    }()
    private let livePhotoButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "livephoto.slash")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityIdentifier = "camera.livePhoto"
        button.accessibilityLabel = String(localized: "live_photo.title")
        button.accessibilityHint = String(localized: "live_photo.hint")
        return button
    }()
    private let livePhotoAudioButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "mic.slash")
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityIdentifier = "camera.livePhotoAudio"
        button.accessibilityLabel = String(localized: "live_photo.audio.title")
        button.accessibilityHint = String(localized: "live_photo.audio.hint")
        return button
    }()
    private let moreButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "gearshape")

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "more.title")
        button.accessibilityIdentifier = "camera.more"
        
        return button
    }()
    private let focusView: FocusView = FocusView()
    
    private let permissionView: PermissionView = {
        let view = PermissionView()
        
        return view
    }()
    
    enum Authorization {
        case notDetermined
        case authorized
        case denied
    }
    
    var cameraPermissionAuthorized: Authorization = .notDetermined {
        didSet {
            runOnMainThreadIfNeeded {
                self.showPermissionViewIfNeeded()
            }
        }
    }
    var addPhotoPermissionAuthorized: Authorization = .notDetermined {
        didSet {
            runOnMainThreadIfNeeded {
                self.showPermissionViewIfNeeded()
            }
        }
    }
    
    private let exposureStops: [Int32] = [
        60, 65, 70, 75, 80, 85, 90, 95,
        100,
        110, 120, 130, 140, 150, 160, 170, 180, 190, 200,
        220, 240, 260, 280, 300,
        325, 350, 375, 400,
        433, 466, 500,
        550, 600,
        650, 700,
        800,
        900,
        1000,
        1100,
        1200,
        1400,
        1600,
        2000, 2500, 3000
    ]
    
    private var iso: Float = 0.0 {
        didSet {
            updateInformationLabel()
        }
    }
    private var lensPosition: Float = 0.0 {
        didSet {
            if abs(lensPosition - lensPositionSlider.value) >= 0.01 {
                lensPositionSlider.value = lensPosition
            }
            updateSliderLabel()
        }
    }
    private var shutterScale: Int32 = 0 {
        didSet {
            updateInformationLabel()
        }
    }
    private var apertureFactor: Float = 0.0 {
        didSet {
            updateInformationLabel()
        }
    }
    
    var orientationLast = UIInterfaceOrientation.portrait
    var motionManager: CMMotionManager?
    
    var observation: NSKeyValueObservation?
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    var isRegularHorizontalSizeClass: Bool {
        return traitCollection.horizontalSizeClass == .regular
    }
    
    deinit {
        observation?.invalidate()
        moonFinder.stop()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .skyColor
        
        view.addSubview(previewView)
        previewView.accessibilityIdentifier = "camera.preview"
        if isRegularHorizontalSizeClass {
            previewView.snp.makeConstraints { make in
                make.leading.equalTo(view).inset(80)
                make.trailing.equalTo(view).inset(80)
                make.centerX.equalTo(view)
                make.top.equalTo(view.safeAreaLayoutGuide).inset(50)
                make.height.greaterThanOrEqualTo(previewView.snp.width).multipliedBy(4.0/3.0)
            }
        } else {
            previewView.snp.makeConstraints { make in
                make.leading.equalTo(view)
                make.trailing.equalTo(view)
                make.centerX.equalTo(view)
                make.top.equalTo(view.safeAreaLayoutGuide).inset(0)
                make.height.greaterThanOrEqualTo(previewView.snp.width).multipliedBy(4.0/3.0)
            }
        }
        
        view.addSubview(captureButton)
        captureButton.snp.makeConstraints { make in
            make.centerX.equalTo(view)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(20)
            make.width.height.equalTo(64.0)
        }
        captureButton.addTarget(self, action: #selector(capturePhoto(_:)), for: .touchUpInside)
        
        view.addSubview(informationLabel)
        informationLabel.snp.makeConstraints { make in
            make.leading.equalTo(view)
            make.trailing.equalTo(view)
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(20)
        }
        
        view.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.centerY.equalTo(captureButton)
            make.trailing.equalTo(captureButton.snp.leading).offset(isRegularHorizontalSizeClass ? -60 : -15)
            make.width.height.equalTo(60)
        }
        minusButton.addTarget(self, action: #selector(minusShutterScale), for: .touchUpInside)
        
        view.addSubview(plusButton)
        plusButton.snp.makeConstraints { make in
            make.centerY.equalTo(captureButton)
            make.leading.equalTo(captureButton.snp.trailing).offset(isRegularHorizontalSizeClass ? 60 : 15)
            make.width.height.equalTo(60)
        }
        plusButton.addTarget(self, action: #selector(plusShutterScale), for: .touchUpInside)
        
        view.addSubview(lensPositionSlider)
        if isRegularHorizontalSizeClass {
            lensPositionSlider.snp.makeConstraints { make in
                make.centerX.equalTo(view)
                make.width.equalTo(450)
                make.bottom.equalTo(captureButton.snp.top).offset(-16)
                make.height.equalTo(40)
            }
        } else {
            lensPositionSlider.snp.makeConstraints { make in
                make.leading.trailing.equalTo(view).inset(20)
                make.bottom.equalTo(captureButton.snp.top).offset(-16)
                make.height.equalTo(40)
            }
        }
        lensPositionSlider.addTarget(self, action: #selector(lensPositionValueChanged(_:)), for: .valueChanged)
        lensPositionSlider.addTarget(self, action: #selector(lensPositionInteractionEnded), for: [.touchUpInside, .touchUpOutside])
        lensPositionSlider.setThumbImage(UIImage(systemName: "rectangle.portrait.fill")?.withTintColor(.moonColor, renderingMode: .alwaysOriginal), for: .normal)
        
        view.addSubview(sliderLabel)
        if view.frame.width == 320 {
            sliderLabel.snp.makeConstraints { make in
                make.leading.equalTo(lensPositionSlider)
                make.top.equalTo(lensPositionSlider.snp.bottom).offset(-5)
            }
        } else {
            sliderLabel.snp.makeConstraints { make in
                make.leading.equalTo(lensPositionSlider)
                make.bottom.equalTo(lensPositionSlider.snp.top).offset(5)
            }
        }
        
        view.addSubview(moreButton)
        if view.frame.width == 320 {
            moreButton.snp.makeConstraints { make in
                make.trailing.equalTo(view)
                make.leading.equalTo(plusButton.snp.trailing)
                make.height.equalTo(plusButton)
                make.top.equalTo(plusButton)
            }
        } else {
            moreButton.snp.makeConstraints { make in
                make.trailing.equalTo(view).inset(8)
                make.height.width.equalTo(plusButton)
                make.top.equalTo(plusButton)
            }
        }
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
        
        view.addSubview(albumButton)
        if view.frame.width == 320 {
            albumButton.snp.makeConstraints { make in
                make.leading.equalTo(view)
                make.trailing.equalTo(minusButton.snp.leading)
                make.height.equalTo(minusButton)
                make.top.equalTo(minusButton)
            }
        } else {
            albumButton.snp.makeConstraints { make in
                make.leading.equalTo(view).inset(8)
                make.height.width.equalTo(minusButton)
                make.top.equalTo(minusButton)
            }
        }
        albumButton.addTarget(self, action: #selector(albumButtonTapped), for: .touchUpInside)
        albumButton.configurationUpdateHandler = { [weak self] button in
            guard let self = self else { return }
            var config = button.configuration
            config?.showsActivityIndicator = self.isProcessing
            
            button.configuration = config
        }
        
        // Permission guidance covers the preview, not the independent controls.
        view.addSubview(permissionView)
        view.addSubview(locationButton)
        locationButton.snp.makeConstraints { make in
            make.leading.equalTo(previewView).inset(6)
            make.height.width.equalTo(44)
            make.bottom.equalTo(previewView).inset(6)
        }
        view.addSubview(locationNameButton)
        locationNameButton.snp.makeConstraints { make in
            make.leading.equalTo(locationButton.snp.trailing).offset(6)
            make.centerY.equalTo(locationButton)
            make.height.equalTo(44)
            make.width.greaterThanOrEqualTo(44)
        }
        locationNameButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        locationNameButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        locationNameButton.addTarget(self, action: #selector(setupCustomLocationName), for: .touchUpInside)
        reloadLocationMenu()
        
        permissionView.snp.makeConstraints { make in
            make.edges.equalTo(previewView)
        }
        permissionView.isHidden = true
        permissionView.cameraClosure = { [weak self] in
            self?.jumpToSettings()
        }
        permissionView.albumClosure = { [weak self] in
            self?.jumpToSettings()
        }
        
        view.addSubview(livePhotoButton)
        view.addSubview(livePhotoAudioButton)
        livePhotoButton.snp.makeConstraints { make in
            make.trailing.equalTo(previewView).inset(6)
            make.centerY.equalTo(locationButton)
            make.width.height.equalTo(44)
        }
        livePhotoAudioButton.snp.makeConstraints { make in
            make.trailing.equalTo(livePhotoButton.snp.leading).offset(-6)
            make.leading.greaterThanOrEqualTo(locationNameButton.snp.trailing).offset(6)
            make.centerY.equalTo(locationButton)
            make.width.height.equalTo(44)
        }
        livePhotoAudioButton.addTarget(self, action: #selector(toggleLivePhotoAudio), for: .touchUpInside)
        livePhotoButton.addTarget(self, action: #selector(toggleLivePhoto), for: .touchUpInside)
        updateLivePhotoButton()

        view.addSubview(moonFinderButton)
        moonFinderButton.snp.makeConstraints { make in
            make.left.equalTo(previewView).inset(6)
            make.top.equalTo(previewView).inset(6)
            make.height.width.equalTo(44)
        }
        moonFinderButton.addTarget(self, action: #selector(toggleMoonFinder), for: .touchUpInside)
        view.addSubview(moonFinderView)
        moonFinderView.snp.makeConstraints { make in
            make.edges.equalTo(previewView)
        }
        view.bringSubviewToFront(moonFinderButton)
        view.addSubview(moonCalendarButton)
        moonCalendarButton.snp.makeConstraints { make in
            make.right.equalTo(previewView).inset(6)
            make.top.equalTo(previewView).inset(6)
            make.height.width.equalTo(44)
        }
        moonCalendarButton.addTarget(self, action: #selector(moonCalendarButtonTapped), for: .touchUpInside)
        moonFinderView.isHidden = true
        moonFinderView.cameraGeometry = { [weak self] in
            guard let self, let device = self.captureDevice,
                  self.previewView.videoPreviewLayer.connection != nil else { return nil }
            let imageRect = self.previewView.videoPreviewLayer.layerRectConverted(
                fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            return (imageRect, Double(device.activeFormat.videoFieldOfView), Double(device.videoZoomFactor))
        }
        moonFinder.onUpdate = { [weak self] state in
            self?.moonFinderView.update(state)
        }
        moonFinderView.settingsAction = { [weak self] in
            self?.closeMoonFinder()
            self?.jumpToSettings()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(closeMoonFinder),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeCameraOverlays),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusTap(_:)))
        previewView.addGestureRecognizer(tapGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoomRecognizer(_:)))
        previewView.addGestureRecognizer(pinchGesture)
        
        initializeMotionManager()
        
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.moonColor
            self.previewView.addSubview(self.spinner)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(ISOUpdated), name: NSNotification.Name.ISOUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshSharePrompt), name: .SettingsUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(whiteBalanceUpdated), name: NSNotification.Name.WhiteBalanceUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadLocationMenu), name: NSNotification.Name.LocationAuthorizationDidChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadLocationMenu), name: NSNotification.Name.LocationInformationDidChanged, object: nil)

        observation = observe(\.presentationController, options: [.old, .new]) { [weak self] _, change in
            print("presentationController changed")
            if let vc = change.newValue as? UIPresentationController {
                if vc.presentedViewController.presentedViewController != nil {
                    self?.stopCaptureSession()
                    self?.stopLocationUpdateIfNeeded()
                } else {
                    self?.resumeCaptureSession()
                    self?.resumeLocationUpdateIfNeeded()
                }
            }
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if view.safeAreaInsets.top > 1.0, previewView.superview != nil {
            if isRegularHorizontalSizeClass {
                previewView.snp.updateConstraints { make in
                    make.top.equalTo(view.safeAreaLayoutGuide).inset(40)
                }
            } else {
                previewView.snp.updateConstraints { make in
                    make.top.equalTo(view.safeAreaLayoutGuide).inset(0)
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isCameraVisible = true
        checkCameraPermissions()
        checkPhotoPremissions()
        setupAndStartCaptureSession()
        resumeCameraOverlays()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isCameraVisible = false
        closeMoonFinder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tutorialController?.view.setNeedsLayout()
    }

    @objc private func toggleMoonFinder() {
        if moonFinder.isActive {
            closeMoonFinder()
        } else {
            moonFinderView.isHidden = false
            moonFinderButton.accessibilityLabel = String(localized: "moon_finder.close")
            moonFinderButton.configuration?.image = UIImage(systemName: "xmark")
            moonFinderButton.accessibilityValue = String(localized: "moon_finder.active")
            moonFinder.start()
            showPermissionViewIfNeeded()
        }
    }

    @objc private func closeMoonFinder() {
        moonFinder.stop()
        moonFinderView.isHidden = true
        moonFinderButton.accessibilityLabel = String(localized: "moon_finder.open")
        moonFinderButton.configuration?.image = UIImage(systemName: "moon.stars")
        moonFinderButton.accessibilityValue = nil
        showPermissionViewIfNeeded()
    }
    
    func initializeMotionManager() {
        guard let current = OperationQueue.current else { return }
        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = 0.2
        motionManager?.gyroUpdateInterval = 0.2
        motionManager?.startAccelerometerUpdates(to: current, withHandler: { [weak self] accelerometerData, error in
            if error == nil {
                self?.outputAccelerationData(accelerometerData?.acceleration)
            } else {
                print(error.debugDescription)
            }
        })
    }
    
    //MARK:- Permissions
    func checkCameraPermissions() {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch cameraAuthStatus {
        case .authorized:
            cameraPermissionAuthorized = .authorized
        case .denied:
            cameraPermissionAuthorized = .denied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (authorized) in
                if authorized {
                    self.cameraPermissionAuthorized = .authorized
                    self.setupAndStartCaptureSession()
                } else {
                    self.cameraPermissionAuthorized = .denied
                }
            })
        case .restricted:
            cameraPermissionAuthorized = .denied
        @unknown default:
            cameraPermissionAuthorized = .denied
        }
    }
    
    func checkPhotoPremissions() {
        let photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch photoAuthStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { authrized in
                if authrized == .authorized || authrized == .limited {
                    self.addPhotoPermissionAuthorized = .authorized
                } else {
                    self.addPhotoPermissionAuthorized = .denied
                }
            }
        case .restricted:
            addPhotoPermissionAuthorized = .denied
        case .denied:
            addPhotoPermissionAuthorized = .denied
        case .authorized:
            addPhotoPermissionAuthorized = .authorized
        case .limited:
            addPhotoPermissionAuthorized = .authorized
        @unknown default:
            addPhotoPermissionAuthorized = .denied
        }
    }
    
    func showPermissionViewIfNeeded() {
        if cameraPermissionAuthorized == .denied {
            permissionView.isHidden = moonFinder.isActive || tutorialController != nil
            permissionView.update(showCameraButton: true, showAlbumButton: false)
            captureButton.isEnabled = false
        } else {
            permissionView.isHidden = true
            updateCaptureControls()
        }
        startTutorialIfNeeded()
    }
    
    //MARK:- Camera Setup
    func setupAndStartCaptureSession() {
        guard cameraPermissionAuthorized == .authorized else {
            return
        }
        
        sessionQueue.async {
            if let session = self.session {
                self.restoreLiveConfiguration()
                if !session.isRunning { session.startRunning() }
                self.publishSessionState()
                return
            }
            //init session
            self.session = AVCaptureSession()
            //start configuration
            self.session?.beginConfiguration()
            
            //session specific configuration
            if self.session?.canSetSessionPreset(.photo) == true {
                self.session?.sessionPreset = .photo
            }
            self.session?.automaticallyConfiguresCaptureDeviceForWideColor = true
            
            //setup inputs
            self.setupInputs()
            
            DispatchQueue.main.async {
                //setup preview layer
                self.setupPreviewView()
            }
            
            //setup output
            self.setupOutput()
            
            //commit configuration
            self.configureLiveAudio(enabled: UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhoto.rawValue))
            self.session?.commitConfiguration()
            //start running it
            self.session?.startRunning()
            self.publishSessionState()
        }
    }
    
    func stopCaptureSession() {
        guard cameraPermissionAuthorized == .authorized else {
            return
        }
        
        sessionQueue.async {
            self.session?.stopRunning()
            self.publishSessionState()
        }
    }
    
    func resumeCaptureSession() {
        guard cameraPermissionAuthorized == .authorized else {
            return
        }
        
        sessionQueue.async {
            self.restoreLiveConfiguration()
            self.session?.startRunning()
            self.publishSessionState()
        }
    }
    
    var lensPositionObservation: NSKeyValueObservation?
    
    func setupInputs(){
        //get back camera
        if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            captureDevice = device
        } else {
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                captureDevice = device
            } else {
                //handle this appropriately for production purposes
                fatalError("no back camera")
            }
        }
        guard let captureDevice = captureDevice else {
            return
        }
        // 检查是否支持ISO设置
        guard captureDevice.isExposureModeSupported(.custom) else {
            // 处理不支持自定义曝光模式的情况
            return
        }
        
        do {
            try captureDevice.lockForConfiguration()
            
            // 监听镜头位置的变化
            lensPositionObservation = captureDevice.observe(\.lensPosition, options: [.new]) { _, change in
                if let newLensPosition = change.newValue {
                    self.lensPosition = newLensPosition
                }
            }
            
            captureDevice.unlockForConfiguration()
        } catch {
            // 处理设备配置错误的情况
        }
        
        // 获取ISO范围
        let minISO = captureDevice.activeFormat.minISO
        let maxISO = captureDevice.activeFormat.maxISO
        
        Camera.shared.update(minISO: minISO, maxISO: maxISO)

        print("\(captureDevice.activeFormat.maxExposureDuration)")
        print("\(captureDevice.activeFormat.minExposureDuration)")
        do {
            try captureDevice.lockForConfiguration()
            
            apertureFactor = captureDevice.lensAperture
            
            // 设置ISO值
            iso = Settings.shared.getISOSettings().isoValue
            // f/2.8 1/200 iso100
            let isoScale = iso / 100.0
            let apertureScale = (2.8 * 2.8) / (apertureFactor * apertureFactor)
            let stop = Int32(200.0 * isoScale * apertureScale)
            
            let initExposureStop = findClosestNumber(to: stop, in: exposureStops)
            shutterScale = initExposureStop
            captureDevice.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: Int32(shutterScale)), iso: iso, completionHandler: nil)
            
            captureDevice.unlockForConfiguration()
        } catch {
            // 处理设备配置错误的情况
        }
        
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isWhiteBalanceModeSupported(.locked) {
                let temperature = Settings.shared.getWhiteBalanceSettings().temperatureValue
                let temperatureAndTintValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
                let deviceGains = captureDevice.deviceWhiteBalanceGains(for: temperatureAndTintValues)
                captureDevice.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
            }
            captureDevice.unlockForConfiguration()
        } catch  {
            // 处理设备配置错误的情况
        }
        
        //now we need to create an input objects from our devices
        guard let bInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            fatalError("could not create input device from back camera")
        }
        captureDeviceInput = bInput
        if session?.canAddInput(bInput) == false {
            fatalError("could not add back camera input to capture session")
        }
        
        //connect back camera input to session
        session?.addInput(bInput)
    }
    
    func setupOutput(){
        guard let captureDevice = captureDevice else {
            return
        }
        if session?.canAddOutput(photoOutput) == true {
            session?.addOutput(photoOutput)
            
            if #available(iOS 16.0, *) {
                if let first = captureDevice.activeFormat.supportedMaxPhotoDimensions.first {
                    photoOutput.maxPhotoDimensions = first
                }
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            photoOutput.maxPhotoQualityPrioritization = .quality
            // Configure once before starting. Toggling only suspends/resumes the
            // Live buffer, so it cannot tear down an in-flight capture pipeline.
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
                if #available(iOS 16.0, *) { photoOutput.preservesLivePhotoCaptureSuspendedOnSessionStop = true }
                photoOutput.isLivePhotoCaptureSuspended = !UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhoto.rawValue)
            }
            liveSupportObservation = photoOutput.observe(\.isLivePhotoCaptureSupported, options: [.new]) { [weak self] _, _ in
                self?.sessionQueue.async { self?.publishSessionState() }
            }
            
            if let connection = photoOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }
    }
    
    func setupPreviewView(){
        previewView.session = session
        // The UI and sensor projection share portrait device coordinates.
        if let connection = previewView.videoPreviewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
    
    func updateInformationLabel() {
        DispatchQueue.main.async {
            self.informationLabel.text = String.localizedStringWithFormat(
                String(localized: "camera.status.summary"),
                self.iso,
                self.apertureFactor,
                self.shutterTimeString(self.shutterScale)
            )
        }
    }
    
    func updateSliderLabel() {
        DispatchQueue.main.async {
            self.sliderLabel.text = String.localizedStringWithFormat(
                String(localized: "camera.focus.position"),
                self.lensPosition
            )
        }
    }
    
    // All AVFoundation configuration stays on sessionQueue; all control state stays on main.
    private func publishSessionState() {
        let ready = session?.isRunning == true && photoOutput.connection(with: .video) != nil
        let supported = photoOutput.isLivePhotoCaptureSupported && photoOutput.isLivePhotoCaptureEnabled
        let audioActive = liveAudioInput != nil
        DispatchQueue.main.async {
            self.sessionReady = ready; self.livePhotoSupported = supported; self.liveAudioActive = audioActive
            self.updateLivePhotoButton(); self.updateCaptureControls()
        }
    }
    private func updateCaptureControls() {
        let idle = !captureBusy && !livePhotoConfiguring && pendingTemporaryPhoto == nil
        captureButton.isEnabled = idle && sessionReady && cameraPermissionAuthorized == .authorized
        livePhotoButton.isEnabled = idle && sessionReady && livePhotoSupported
        livePhotoAudioButton.isEnabled = idle && sessionReady && livePhotoSupported && livePhotoEnabled
        for button in [albumButton, moreButton, moonCalendarButton, moonFinderButton] { button.isEnabled = !captureBusy }
    }
    private func updateLivePhotoButton() {
        let active = livePhotoEnabled && livePhotoSupported
        livePhotoButton.configuration?.image = UIImage(systemName: active ? "livephoto" : "livephoto.slash")
        livePhotoButton.tintColor = liveRecording ? .systemRed : active ? .systemYellow : .moonColor
        livePhotoButton.alpha = active ? 1 : 0.65
        livePhotoButton.isSelected = active
        let key = !livePhotoSupported ? "live_photo.unavailable" : liveRecording ? "live_photo.recording" : active ? "live_photo.on" : "live_photo.off"
        livePhotoButton.accessibilityValue = String(localized: String.LocalizationValue(key))
        let audible = active && liveAudioActive
        livePhotoAudioButton.configuration?.image = UIImage(systemName: audible ? "mic" : "mic.slash")
        livePhotoAudioButton.tintColor = audible ? .systemYellow : .moonColor
        livePhotoAudioButton.alpha = audible ? 1 : 0.65
        livePhotoAudioButton.isSelected = audible
        livePhotoAudioButton.accessibilityValue = String(localized: String.LocalizationValue(audible ? "live_photo.audio.on" : "live_photo.audio.off"))
    }
    private func restoreLiveConfiguration() {
        guard let session, inProgressPhotoCaptureDelegates.isEmpty else { return }
        let enabled = UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhoto.rawValue)
        session.beginConfiguration()
        configureLiveAudio(enabled: enabled && photoOutput.isLivePhotoCaptureSupported)
        if photoOutput.isLivePhotoCaptureSupported {
            photoOutput.isLivePhotoCaptureEnabled = true
            photoOutput.isLivePhotoCaptureSuspended = !enabled
        }
        session.commitConfiguration()
    }
    private func configureLiveAudio(enabled: Bool) {
        guard let session else { return }
        if enabled && UserDefaults.standard.bool(forKey: UserDefaults.Custom.LivePhotoAudio.rawValue)
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            if liveAudioInput == nil, let device = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input); liveAudioInput = input
            }
        } else if let input = liveAudioInput {
            session.removeInput(input); liveAudioInput = nil
        }
    }
    private func applyLiveConfiguration(enabled: Bool, audio: Bool) {
        livePhotoConfiguring = true; updateCaptureControls()
        sessionQueue.async {
            guard let session = self.session, self.inProgressPhotoCaptureDelegates.isEmpty,
                  self.photoOutput.isLivePhotoCaptureSupported, self.photoOutput.isLivePhotoCaptureEnabled else {
                DispatchQueue.main.async { self.livePhotoConfiguring = false; self.updateCaptureControls() }
                return
            }
            UserDefaults.standard.set(audio, forKey: UserDefaults.Custom.LivePhotoAudio.rawValue)
            session.beginConfiguration()
            self.configureLiveAudio(enabled: enabled)
            self.photoOutput.isLivePhotoCaptureSuspended = !enabled
            session.commitConfiguration()
            UserDefaults.standard.set(enabled, forKey: UserDefaults.Custom.LivePhoto.rawValue)
            let hasAudio = self.liveAudioInput != nil
            DispatchQueue.main.async {
                self.livePhotoEnabled = enabled; self.livePhotoAudioEnabled = audio; self.liveAudioActive = hasAudio; self.livePhotoConfiguring = false
                self.updateLivePhotoButton(); self.updateCaptureControls()
                let key = enabled ? (hasAudio ? "live_photo.on" : "live_photo.silent") : "live_photo.off"
                self.showToast(text: String(localized: String.LocalizationValue(key)))
            }
        }
    }
    @objc private func toggleLivePhoto() {
        guard !captureBusy, !livePhotoConfiguring, livePhotoSupported, sessionReady else { return }
        applyLiveConfiguration(enabled: !livePhotoEnabled, audio: livePhotoAudioEnabled)
    }
    @objc private func toggleLivePhotoAudio() {
        guard livePhotoEnabled, !captureBusy, !livePhotoConfiguring, livePhotoSupported, sessionReady else { return }
        if liveAudioActive {
            applyLiveConfiguration(enabled: true, audio: false); return
        }
        let enable = { [weak self] (allowed: Bool) in
            DispatchQueue.main.async {
                guard let self else { return }
                if allowed { self.applyLiveConfiguration(enabled: true, audio: true) }
                else {
                    self.livePhotoConfiguring = false; self.updateCaptureControls()
                    self.showToast(text: String(localized: "live_photo.audio.denied"))
                }
            }
        }
        // Merely enabling Live never asks for or captures microphone audio.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: enable(true)
        case .notDetermined:
            livePhotoConfiguring = true; updateCaptureControls()
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: enable)
        default: enable(false)
        }
    }
    private func showCaptureError(_ error: Error) {
        LivePhotoRecovery.present(error: error, in: self)
    }
    func presentTemporaryPhoto(_ photo: CapturedPhoto) {
        moonSharePrompt.discardPreviousCapture()
        pendingTemporaryPhoto = photo
        if tutorialController != nil { finishTutorial() }
        showPendingTemporaryPhoto()
    }

    func handleSavedCapture(_ photo: CapturedPhoto, outcome: CaptureSaveOutcome) {
        if outcome.needsTemporaryDetail {
            presentTemporaryPhoto(photo)
        } else {
            moonSharePrompt.consider(photo)
            if outcome.localSaved && !outcome.photosSaved {
                showToast(text: String(localized: "capture.saved_locally"))
            }
            showPendingTemporaryPhoto()
        }
    }

    private func showPendingTemporaryPhoto() {
        moonSharePrompt.refreshPreferences()
        guard let photo = pendingTemporaryPhoto ?? moonSharePrompt.pendingPhoto,
              isCameraVisible, viewIfLoaded?.window != nil, !captureBusy, !livePhotoConfiguring,
              tutorialController == nil, presentedViewController == nil,
              UIApplication.shared.applicationState == .active else {
            updateCaptureControls()
            return
        }
        let isSaved = pendingTemporaryPhoto == nil
        let detail = ImageDetailViewController(capturedPhoto: photo, isSaved: isSaved)
        pendingTemporaryPhoto = nil
        present(detail, animated: true) { [weak self, weak detail] in
            if isSaved, detail?.viewIfLoaded?.window != nil { self?.moonSharePrompt.markPresented() }
        }
        updateCaptureControls()
    }

    @objc private func refreshSharePrompt() {
        moonSharePrompt.refreshPreferences()
    }

    @objc private func offerPendingLivePhotos() {
        if pendingTemporaryPhoto != nil || moonSharePrompt.pendingPhoto != nil {
            showPendingTemporaryPhoto()
            return
        }
        LivePhotoRecovery.offer(in: self) { [weak self] in
            self?.captureBusy == false && self?.livePhotoConfiguring == false
                && self?.tutorialController == nil && self?.isCameraVisible == true
        }
    }

    @objc private func resumeCameraOverlays() {
        moonSharePrompt.refreshPreferences()
        startTutorialIfNeeded()
        offerPendingLivePhotos()
    }

    //MARK:- Actions
    @objc
    func capturePhoto(_ sender: UIButton?) {
        guard let videoPreviewLayerOrientation = AVCaptureVideoOrientation(interfaceOrientation: orientationLast) else {
            return
        }
        guard cameraPermissionAuthorized == .authorized else {
            return
        }
        guard !captureBusy, !livePhotoConfiguring, pendingTemporaryPhoto == nil, sessionReady else { return }
        // Clear an earlier share candidate before completing the tutorial,
        // which may itself try to present a waiting photo.
        moonSharePrompt.discardPreviousCapture()
        didPerformTutorialAction(.capture)
        let wantsLivePhoto = livePhotoEnabled
        // Begin before AVFoundation starts recording, not after its callbacks.
        let backgroundTask = wantsLivePhoto ? LivePhotoBackgroundTask() : nil
        captureBusy = true; isProcessing = true; updateCaptureControls()
        sessionQueue.async {
            var handedOff = false
            defer { if !handedOff { backgroundTask?.end() } }
            guard self.session?.isRunning == true else {
                DispatchQueue.main.async { self.captureBusy = false; self.isProcessing = false; self.updateCaptureControls() }; return
            }
            var resources: LivePhotoResources?
            if wantsLivePhoto {
                guard self.photoOutput.isLivePhotoCaptureEnabled, self.photoOutput.isLivePhotoCaptureSupported,
                      !self.photoOutput.isLivePhotoCaptureSuspended else {
                    DispatchQueue.main.async {
                        self.captureBusy = false; self.isProcessing = false; self.updateCaptureControls()
                        self.showCaptureError(ImageSaver.LivePhotoSaveError.missingMovie)
                    }; return
                }
                do { resources = try LivePhotoResources() }
                catch {
                    DispatchQueue.main.async { self.captureBusy = false; self.isProcessing = false; self.updateCaptureControls(); self.showCaptureError(error) }
                    return
                }
            }
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
            }
            var photoSettings = AVCapturePhotoSettings()
            
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            if self.captureDeviceInput?.device.isFlashAvailable == true {
                photoSettings.flashMode = .off
            }
            
            if #available(iOS 16.0, *) { photoSettings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions }
            else { photoSettings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled }
            photoSettings.livePhotoMovieFileURL = resources?.movieURL
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            
            photoSettings.photoQualityPrioritization = .speed
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, resources: resources, backgroundTask: backgroundTask, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    self.isProcessing = true
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor, error, capturedPhoto in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
                DispatchQueue.main.async {
                    self.isProcessing = false; self.captureBusy = false
                    self.updateCaptureControls()
                    if let capturedPhoto, let outcome = photoCaptureProcessor.saveOutcome {
                        self.handleSavedCapture(capturedPhoto, outcome: outcome)
                    } else if let error { self.showCaptureError(error) }
                }
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                DispatchQueue.main.async {
                    if animate {
                        self.spinner.hidesWhenStopped = true
                        self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                        self.spinner.startAnimating()
                    } else {
                        self.spinner.stopAnimating()
                    }
                }
            }, liveRecordingHandler: { recording in
                DispatchQueue.main.async { self.liveRecording = recording; self.updateLivePhotoButton() }
            })
            
            photoCaptureProcessor.location = Location.shared.location
            
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            handedOff = true
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    @objc
    func lensPositionValueChanged(_ sender: UISlider) {
        let value = sender.value
        sessionQueue.async {
            self.update(lensPosition: value)
        }
        if sender.isTracking {
            tutorialFocusSliderMoved = true
        } else {
            // VoiceOver adjusts a slider without a touch-up event.
            didPerformTutorialAction(.focus)
        }
    }

    @objc private func lensPositionInteractionEnded() {
        guard tutorialFocusSliderMoved else { return }
        tutorialFocusSliderMoved = false
        didPerformTutorialAction(.focus)
    }
    
    func update(lensPosition: Float) {
        guard let captureDevice = captureDevice else {
            return
        }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.setFocusModeLocked(lensPosition: lensPosition, completionHandler: nil)
            captureDevice.unlockForConfiguration()
        }
        catch {
            print(error)
        }
    }
    
    @objc
    func ISOUpdated() {
        guard let captureDevice = captureDevice else {
            return
        }
        iso = Settings.shared.getISOSettings().isoValue
        sessionQueue.async {
            do {
                try captureDevice.lockForConfiguration()
                captureDevice.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: Int32(self.shutterScale)), iso: self.iso, completionHandler: nil)
                captureDevice.unlockForConfiguration()
            }
            catch {
                print(error)
            }
        }
    }
    
    @objc
    func whiteBalanceUpdated() {
        guard let captureDevice = captureDevice else {
            return
        }
        let temperature = Settings.shared.getWhiteBalanceSettings().temperatureValue
        sessionQueue.async {
            do {
                try captureDevice.lockForConfiguration()
                if captureDevice.isWhiteBalanceModeSupported(.locked) {
                    let temperatureAndTintValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
                    let deviceGains = captureDevice.deviceWhiteBalanceGains(for: temperatureAndTintValues)
                    captureDevice.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
                }
                captureDevice.unlockForConfiguration()
            } catch  {
                // 处理设备配置错误的情况
            }
        }
    }
    
    func showToast(text: String) {
        view.hideAllToasts()
        var style = ToastStyle()
        style.backgroundColor = .black.withAlphaComponent(0.8)
        style.messageAlignment = .center
        style.messageFont = UIFont.systemFont(ofSize: 12)
        style.messageColor = .moonColor
        view.makeToast(text, duration: 0.5, point: CGPoint(x: captureButton.frame.midX, y: captureButton.frame.minY - 100), title: nil, image: nil, style: style, completion: nil)
    }
    
    func shutterTimeString(_ time: Int32) -> String {
        return String.localizedStringWithFormat(
            String(localized: "camera.shutter_speed.value"),
            time
        )
    }
    
    @objc
    func plusShutterScale() {
        defer { didPerformTutorialAction(.exposure) }
        guard let first = exposureStops.first else { return }
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex != 0 ? exposureStops[currentIndex - 1] : first
            if currentIndex == 0 {
                showToast(text: String(localized: "camera.shutter_speed.maximum_reached"))
            } else {
                showToast(text: shutterTimeString(nextStop))
            }
            sessionQueue.async {
                self.update(shutterScale: nextStop)
            }
        }
    }
    
    @objc
    func minusShutterScale() {
        defer { didPerformTutorialAction(.exposure) }
        guard let last = exposureStops.last else { return }
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex + 1 < exposureStops.count ? exposureStops[currentIndex + 1] : last
            if currentIndex + 1 == exposureStops.count {
                showToast(text: String(localized: "camera.shutter_speed.minimum_reached"))
            } else {
                showToast(text: shutterTimeString(nextStop))
            }
            sessionQueue.async {
                self.update(shutterScale: nextStop)
            }
        }
    }
    
    func update(shutterScale: Int32) {
        guard let captureDevice = captureDevice else {
            return
        }
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: Int32(shutterScale)), iso: iso, completionHandler: nil)
            captureDevice.unlockForConfiguration()
            self.shutterScale = shutterScale
        }
        catch {
            print(error)
        }
    }
    
    @objc
    func focusTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        let location = gestureRecognizer.location(in: gestureRecognizer.view)
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
        addFocusViewAt(location)
        sessionQueue.async {
            if let device = self.captureDeviceInput?.device {
                do {
                    try device.lockForConfiguration()
                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = devicePoint
                        device.focusMode = .autoFocus
                    }
                    device.unlockForConfiguration()
                }
                catch {
                    print(error)
                }
            }
        }
        didPerformTutorialAction(.tapFocus)
    }
    
    func addFocusViewAt(_ location: CGPoint) {
        if focusView.superview != nil {
            focusView.removeFromSuperview()
        }
        previewView.addSubview(focusView)
        focusView.snp.makeConstraints { make in
            make.centerX.equalTo(previewView.snp.leading).inset(location.x)
            make.centerY.equalTo(previewView.snp.top).inset(location.y)
            make.width.height.equalTo(60)
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
            self.focusView.removeFromSuperview()
        }
    }
    
    func findClosestNumber(to target: Int32, in numbers: [Int32]) -> Int32 {
        var closestNumber: Int32 = 0
        var minDifference = Int32.max
        
        for number in numbers {
            let difference = abs(number - target)
            
            if difference < minDifference {
                closestNumber = number
                minDifference = difference
            } else if difference == minDifference, number > closestNumber {
                closestNumber = number
            }
        }
        
        return closestNumber
    }
    
    var pivotPinchScale: CGFloat = 0.0
    
    @objc
    func handlePinchToZoomRecognizer(_ gesture: UIPinchGestureRecognizer) {
        // An ended pinch can already have zero touches. Observe it before the
        // hardware/touch-count guards, and don't advance on cancellation.
        if gesture.state == .ended, abs(gesture.scale - 1) > 0.01 {
            didPerformTutorialAction(.zoom)
        }
        guard let captureDevice = captureDevice else {
            return
        }
        
        guard gesture.numberOfTouches == 2 else {
            return
        }
        
        switch gesture.state {
        case .began:
            pivotPinchScale = captureDevice.videoZoomFactor
        case .changed:
            do {
                try captureDevice.lockForConfiguration()
                var factor = self.pivotPinchScale * gesture.scale
                factor = max(1, min(factor, captureDevice.activeFormat.videoMaxZoomFactor))
                captureDevice.videoZoomFactor = factor
                captureDevice.unlockForConfiguration()
                moonFinderView.setNeedsLayout()
            } catch {
                NSLog("error: \(error)")
            }
        default:
            break
        }
    }
    
    func outputAccelerationData(_ acceleration: CMAcceleration?) {
        guard let acceleration = acceleration else { return }
        
        let orientationNew: UIInterfaceOrientation
        
        let threshold = 0.75 // 方向判断的阈值

        if acceleration.x >= threshold {
            orientationNew = .landscapeLeft
        } else if acceleration.x <= -threshold {
            orientationNew = .landscapeRight
        } else if acceleration.y <= -threshold {
            orientationNew = .portrait
        } else if acceleration.y > threshold {
            orientationNew = .portraitUpsideDown
        } else {
            // Consider same as last time
            return
        }
        
        if orientationNew != orientationLast {
            orientationLast = orientationNew
        } else {
            return
        }
    }
    
    @objc
    func moreButtonTapped() {
        closeMoonFinder()
        let settingsVC = makeMorePageViewController(onShowTutorial: { [weak self] in
            self?.restartTutorial()
        })
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }
    
    @objc
    func albumButtonTapped() {
        guard isProcessing == false else { return }
        closeMoonFinder()
        let albumVC = AlbumViewController()
        let nav = UINavigationController(rootViewController: albumVC)
        present(nav, animated: true)
    }
    
    @objc
    private func moonCalendarButtonTapped() {
        closeMoonFinder()
        let nav = UINavigationController(rootViewController: MoonCalendarViewController())
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    func jumpToSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
           return
        }
        if UIApplication.shared.canOpenURL(url) {
           UIApplication.shared.open(url, options: [:])
        }
    }
    
    func runOnMainThreadIfNeeded(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            // 当前线程是主线程，直接执行代码块
            block()
        } else {
            DispatchQueue.main.async {
                // 切换到主线程执行代码块
                block()
            }
        }
    }
}

extension CameraViewController {
    func didPerformTutorialAction(_ step: CameraTutorialStep) {
        tutorialController?.didPerform(step)
    }

    @objc
    func reloadLocationMenu() {
        let authorization = Location.shared.authorizationStatus()
        let authorized = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        let active = authorized && !Location.shared.manualDisable
        locationButton.configuration?.image = UIImage(systemName: active ? "mappin.and.ellipse" : "mappin.slash")
        locationButton.tintColor = active ? .systemYellow : .moonColor
        locationButton.alpha = active ? 1 : 0.65
        locationButton.isSelected = active
        locationNameButton.isHidden = !active
        locationNameButton.isSelected = active
        locationNameButton.tintColor = locationButton.tintColor
        let name = CustomSettings.shared.locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "location.title")
        locationNameButton.configuration?.title = title
        locationNameButton.accessibilityLabel = title
        
        var menuChildren: [UIMenuElement] = []
        
        switch authorization {
        case .notDetermined:
            let requestPermissionAction = UIAction(title: String(localized: "location.permission.request_access"), image: UIImage(systemName: "mappin.circle")) { _ in
                Location.shared.requestAuthorization()
            }
            menuChildren.append(requestPermissionAction)
        case .restricted, .denied:
            let settingsAction = UIAction(title: String(localized: "location.permission.denied"), image: UIImage(systemName: "gearshape.circle")) { [weak self] _ in
                self?.jumpToSettings()
            }
            menuChildren.append(settingsAction)
        case .authorizedAlways, .authorizedWhenInUse:
            if Location.shared.manualDisable {
                let enableAction = UIAction(title: String(localized: "location.metadata.enable"), image: UIImage(systemName: "mappin.circle")) { _ in
                    Location.shared.manual(disable: false)
                }
                menuChildren.append(enableAction)
            } else {
                let disableAction = UIAction(title: String(localized: "location.metadata.disable"), image: UIImage(systemName: "mappin.slash.circle")) { _ in
                    Location.shared.manual(disable: true)
                }
                menuChildren.append(disableAction)
            }
        @unknown default:
            break
        }
        
        let customNameAction = UIAction(title: CustomSettings.shared.locationName ?? "", image: UIImage(systemName: "rectangle.and.pencil.and.ellipsis")) { [weak self] action in
            self?.setupCustomLocationName()
        }
        if #available(iOS 16.0, *) {
            customNameAction.subtitle = String(localized: "location.custom.intro")
        }
        
        let divider = UIMenu(title: String(localized: "location.custom.title"), options: . displayInline, children: [customNameAction])
        
        menuChildren.append(divider)
        
        locationButton.menu = UIMenu(children: menuChildren)
    }
    
    func stopLocationUpdateIfNeeded() {
        Location.shared.stopLocationUpdate()
    }
    
    func resumeLocationUpdateIfNeeded() {
        Location.shared.resumeLocationUpdate()
    }
    
    @objc func setupCustomLocationName() {
        guard presentedViewController == nil else { return }
        let alertController = UIAlertController(title: String(localized: "location.custom.title"), message: String(localized: "location.custom.input.message"), preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = ""
            textField.text = CustomSettings.shared.locationName
        }
        let cancelAction = UIAlertAction(title: String(localized: "action.cancel"), style: .cancel) { _ in
            //
        }
        let okAction = UIAlertAction(title: String(localized: "action.ok"), style: .default) { [weak self] _ in
            if let text = alertController.textFields?.first?.text {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                CustomSettings.shared.locationName = name.isEmpty ? nil : name
                self?.reloadLocationMenu()
            } else {
                //
            }
        }

        alertController.addAction(cancelAction)
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }
}

extension UIAlertController {
    @objc
    func textDidChangeInContentAlert() {
        if let keyword = textFields?[0].text, let action = actions.last {
            action.isEnabled = keyword.isValidLocationName()
        }
    }
}

extension String {
    func isValidLocationName() -> Bool{
        return count > 0 && count < 150
    }
}

extension CameraViewController {
    /// Settings returns to the existing camera, retaining its zoom and exposure.
    func restartTutorial() {
        tutorialRequested = true
        guard tutorialController == nil else { return }
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in self?.startTutorialIfNeeded() }
        } else {
            startTutorialIfNeeded()
        }
    }

    private func startTutorialIfNeeded() {
        guard tutorialController == nil, tutorialRequested || !hasPresentedAutomaticGuide,
              isCameraVisible, viewIfLoaded?.window != nil, presentedViewController == nil,
              UIApplication.shared.applicationState == .active,
              cameraPermissionAuthorized != .notDetermined, addPhotoPermissionAuthorized != .notDetermined,
              !captureBusy, !livePhotoConfiguring, pendingTemporaryPhoto == nil,
              moonSharePrompt.pendingPhoto == nil else { return }
        let tip = !tutorialRequested && !tutorialProgress.shouldPresent
            ? tutorialProgress.unseenTips.randomElement() : nil
        guard tutorialRequested || tutorialProgress.shouldPresent || tip != nil else { return }
        let guide = TutorialsViewController(steps: tip.map { [$0] } ?? CameraTutorialStep.basics, isTip: tip != nil)
        hasPresentedAutomaticGuide = true
        tutorialController = guide
        closeMoonFinder()
        guide.targetRects = { [weak self] step, overlay in
            self?.tutorialTargets(for: step, in: overlay) ?? []
        }
        guide.interactionViews = { [weak self] step in self?.tutorialInteractionViews(for: step) ?? [] }
        guide.onFinish = { [weak self] in self?.finishTutorial() }
        guide.onShowStep = { [weak self] step in
            guard let self else { return }
            if tip != nil { self.tutorialProgress.recordTipShown(step) }
            let controls = tip == nil ? self.tutorialInteractionViews(for: step) : []
            self.tutorialAccessibility.forEach {
                $0.0.accessibilityElementsHidden = $0.1 || !controls.contains($0.0)
            }
        }
        // Expose the current control to VoiceOver alongside the tip.
        tutorialAccessibility = view.subviews.map { ($0, $0.accessibilityElementsHidden) }
        tutorialAccessibility.forEach { $0.0.accessibilityElementsHidden = true }
        addChild(guide)
        view.addSubview(guide.view)
        guide.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        guide.didMove(toParent: self)
        view.layoutIfNeeded()
    }

    private func finishTutorial() {
        guard let guide = tutorialController else { return }
        if !guide.isTip { tutorialProgress.complete() }
        tutorialRequested = false
        guide.willMove(toParent: nil)
        guide.view.removeFromSuperview()
        guide.removeFromParent()
        tutorialController = nil
        tutorialAccessibility.forEach { $0.0.accessibilityElementsHidden = $0.1 }
        tutorialAccessibility.removeAll()
        showPermissionViewIfNeeded()
        UIAccessibility.post(notification: .screenChanged,
                             argument: permissionView.isHidden ? captureButton : permissionView)
        offerPendingLivePhotos()
    }

    private func tutorialTargets(for step: CameraTutorialStep, in overlay: UIView) -> [CGRect] {
        func rect(_ target: UIView) -> CGRect { target.convert(target.bounds, to: overlay) }
        switch step {
        case .zoom, .tapFocus:
            let preview = rect(previewView)
            let size = CGSize(width: min(preview.width - 48, 260), height: min(preview.height * 0.3, 160))
            return [CGRect(x: preview.midX - size.width / 2, y: preview.midY - size.height / 2,
                           width: size.width, height: size.height)]
        case .focus:
            return [rect(lensPositionSlider)]
        case .exposure:
            return [rect(minusButton), rect(plusButton)]
        case .livePhoto:
            return [rect(livePhotoButton)]
        case .location:
            return [rect(locationButton)]
        case .moonFinder:
            return [rect(moonFinderButton)]
        case .moonCalendar:
            return [rect(moonCalendarButton)]
        case .capture:
            return [rect(captureButton)]
        case .album:
            return [rect(albumButton)]
        case .settings:
            return [rect(moreButton)]
        }
    }

    private func tutorialInteractionViews(for step: CameraTutorialStep) -> [UIView] {
        switch step {
        case .zoom, .tapFocus: return [previewView]
        case .focus: return [lensPositionSlider]
        case .exposure: return [minusButton, plusButton]
        case .capture: return [captureButton]
        default: return []
        }
    }
}
