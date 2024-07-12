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

class CameraViewController: UIViewController {
    private var session: AVCaptureSession!
    private let sessionQueue = DispatchQueue(label: "capture")
    
    private var captureDevice: AVCaptureDevice?
    private var captureDeviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var spinner: UIActivityIndicatorView!
    private let previewView: AVCaptureVideoPreviewView = AVCaptureVideoPreviewView()
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
        button.accessibilityLabel = String(localized: "Capture")

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
        var configuration = UIButton.Configuration.bordered()
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePlacement = .top
        configuration.imagePadding = 10.0
        configuration.title = String(localized: "Lighten")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12)

            return outgoing
        })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0)
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "Lighten Image")
        
        return button
    }()
    private let minusButton: UIButton = {
        var configuration = UIButton.Configuration.bordered()
        configuration.image = UIImage(systemName: "minus")
        configuration.imagePlacement = .top
        configuration.imagePadding = 10.0
        configuration.title = String(localized: "Darken")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12)

            return outgoing
        })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0)

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "Darken Image")
        
        return button
    }()
    private let lensPositionSlider: UISlider = {
        var slider = UISlider()
        slider.minimumTrackTintColor = .moonColor.withAlphaComponent(0.83)
        slider.accessibilityLabel = String(localized: "Focus Slider")

        return slider
    }()
    private let sliderLabel: UILabel = {
        var label = UILabel()
        label.text = String(localized: "Focus Slider")
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .moonColor.withAlphaComponent(0.75)
        label.isUserInteractionEnabled = false
        
        return label
    }()
    private let moreButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.imagePlacement = .top
        configuration.imagePadding = 10.0
        configuration.title = String(localized: "More")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12)

            return outgoing
        })
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0)

        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "More")
        
        return button
    }()
    private let tutorialsButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "questionmark.circle")
        configuration.contentInsets = .zero
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        button.accessibilityLabel = String(localized: "Tutorials")
        button.alpha = 0.83
        
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
    
    var orientationLast = UIInterfaceOrientation.unknown
    var motionManager: CMMotionManager?
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    var isRegularHorizontalSizeClass: Bool {
        return traitCollection.horizontalSizeClass == .regular
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .skyColor
        
        view.addSubview(previewView)
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
        
        view.addSubview(tutorialsButton)
        if view.frame.width == 320 {
            tutorialsButton.snp.makeConstraints { make in
                make.leading.equalTo(view)
                make.trailing.equalTo(minusButton.snp.leading)
                make.height.equalTo(minusButton)
                make.top.equalTo(minusButton)
            }
        } else {
            tutorialsButton.snp.makeConstraints { make in
                make.leading.equalTo(view).inset(8)
                make.height.width.equalTo(minusButton)
                make.top.equalTo(minusButton)
            }
        }
        tutorialsButton.addTarget(self, action: #selector(tutorialsButtonTapped), for: .touchUpInside)
        
        view.addSubview(permissionView)
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
        NotificationCenter.default.addObserver(self, selector: #selector(whiteBalanceUpdated), name: NSNotification.Name.WhiteBalanceUpdated, object: nil)
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
        checkCameraPermissions()
        checkPhotoPremissions()
        setupAndStartCaptureSession()
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
                if authrized == .authorized {
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
            addPhotoPermissionAuthorized = .denied
        @unknown default:
            addPhotoPermissionAuthorized = .denied
        }
    }
    
    func showPermissionViewIfNeeded() {
        if cameraPermissionAuthorized == .denied || addPhotoPermissionAuthorized == .denied {
            permissionView.isHidden = false
            permissionView.update(showCameraButton: cameraPermissionAuthorized == .denied, showAlbumButton: addPhotoPermissionAuthorized == .denied)
            captureButton.isEnabled = false
        } else {
            permissionView.isHidden = true
            captureButton.isEnabled = true
        }
    }
    
    //MARK:- Camera Setup
    func setupAndStartCaptureSession() {
        guard cameraPermissionAuthorized == .authorized else {
            return
        }
        
        sessionQueue.async {
            //init session
            self.session = AVCaptureSession()
            //start configuration
            self.session.beginConfiguration()
            
            //session specific configuration
            if self.session.canSetSessionPreset(.photo) {
                self.session.sessionPreset = .photo
            }
            self.session.automaticallyConfiguresCaptureDeviceForWideColor = true
            
            //setup inputs
            self.setupInputs()
            
            DispatchQueue.main.async {
                //setup preview layer
                self.setupPreviewView()
            }
            
            //setup output
            self.setupOutput()
            
            //commit configuration
            self.session.commitConfiguration()
            //start running it
            self.session.startRunning()
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
        if !session.canAddInput(captureDeviceInput) {
            fatalError("could not add back camera input to capture session")
        }
        
        //connect back camera input to session
        session.addInput(captureDeviceInput)
    }
    
    func setupOutput(){
        guard let captureDevice = captureDevice else {
            return
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            if #available(iOS 16.0, *) {
                if let first = captureDevice.activeFormat.supportedMaxPhotoDimensions.first {
                    photoOutput.maxPhotoDimensions = first
                }
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            photoOutput.maxPhotoQualityPrioritization = .quality
            
            if let connection = photoOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }
    }
    
    func setupPreviewView(){
        previewView.session = session
    }
    
    func updateInformationLabel() {
        DispatchQueue.main.async {
            self.informationLabel.text = String(format: String(localized: "ISO: %.0f, Aperture: F/%.1f, %@") ,self.iso, self.apertureFactor, self.shutterTimeString(self.shutterScale))
        }
    }
    
    func updateSliderLabel() {
        DispatchQueue.main.async {
            self.sliderLabel.text = String(format: String(localized: "Focus Slider [Position: %.4f]"), self.lensPosition)
        }
    }
    
    //MARK:- Actions
    @objc
    func capturePhoto(_ sender: UIButton?) {
        guard let videoPreviewLayerOrientation = AVCaptureVideoOrientation(interfaceOrientation: orientationLast) else {
            return
        }
        guard cameraPermissionAuthorized == .authorized, addPhotoPermissionAuthorized == .authorized else {
            return
        }
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            
            if self.captureDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .off
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            
            photoSettings.photoQualityPrioritization = .speed
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
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
            }
            )
            
            photoCaptureProcessor.location = Location.shared.location
            
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    @objc
    func lensPositionValueChanged(_ sender: UISlider) {
        let value = sender.value
        sessionQueue.async {
            self.update(lensPosition: value)
        }
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
        return String(format: String(localized: "Shutter Speed: 1/%is"), time)
    }
    
    @objc
    func plusShutterScale() {
        guard let first = exposureStops.first else { return }
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex != 0 ? exposureStops[currentIndex - 1] : first
            if currentIndex == 0 {
                showToast(text: String(localized: "Maximum Shutter Speed Value Reached"))
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
        guard let last = exposureStops.last else { return }
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex + 1 < exposureStops.count ? exposureStops[currentIndex + 1] : last
            if currentIndex + 1 == exposureStops.count {
                showToast(text: String(localized: "Minimum Shutter Speed Value Reached"))
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
        let location = gestureRecognizer.location(in: gestureRecognizer.view)
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location)
        addFocusViewAt(location)
        sessionQueue.async {
            let device = self.captureDeviceInput.device
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
        let settingsVC = MoreViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }
    
    @objc
    func tutorialsButtonTapped() {
        let tutorialsVC = TutorialsViewController()
        let nav = UINavigationController(rootViewController: tutorialsVC)
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
