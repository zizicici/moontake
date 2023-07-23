//
//  ViewController.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//

import AVKit
import Photos
import SnapKit
import UIKit

class ViewController: UIViewController {
    private var session: AVCaptureSession!
    private let sessionQueue = DispatchQueue(label: "capture")

    private var captureDevice: AVCaptureDevice!
    private var captureDeviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var spinner: UIActivityIndicatorView!
    private let previewView: AVCaptureVideoPreviewView = AVCaptureVideoPreviewView()
    private let captureButton : UIButton = {
        let button = ColorHighlightButton()
        button.normalColor = .moonColor
        button.highlightedColor = .moonColor.withAlphaComponent(0.6)
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.moonColor.cgColor
        button.layer.shadowOpacity = 1.0
        button.layer.shadowOffset = CGSize(width: 0, height: 0)
        button.layer.shadowRadius = 10.0
        button.layer.masksToBounds = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let hintLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.textColor = .moonColor
        label.numberOfLines = 1
        
        return label
    }()
    let plusButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "plus")
        configuration.contentInsets = .zero
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        
        return button
    }()
    let minusButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "minus")
        configuration.contentInsets = .zero
        
        let button = UIButton(configuration: configuration)
        button.tintColor = .moonColor
        
        return button
    }()
    let lensPositionSlider: UISlider = {
        var slider = UISlider()
        slider.minimumTrackTintColor = .moonColor
        
        return slider
    }()
    private let focusView: FocusView = FocusView()
    private let exposureStops: [Int32] = [
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
        2000,
    ]
    
    private var iso: Float = 0.0 {
        didSet {
            updateHintLabel()
        }
    }
    private var lensPosition: Float = 0.0 {
        didSet {
            if abs(lensPosition - lensPositionSlider.value) <= 0.01 {
                lensPositionSlider.value = lensPosition
            }
            updateHintLabel()
        }
    }
    private var shutterScale: Int32 = 0 {
        didSet {
            updateHintLabel()
        }
    }
    private var apertureFactor: Float = 0.0 {
        didSet {
            updateHintLabel()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .skyColor
        view.addSubview(captureButton)
        
        captureButton.snp.makeConstraints { make in
            make.centerX.equalTo(view)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(20)
            make.width.equalTo(60.0)
            make.height.equalTo(60.0)
        }
        captureButton.addTarget(self, action: #selector(captureImage(_:)), for: .touchUpInside)
        
        view.addSubview(previewView)
        previewView.snp.makeConstraints { make in
            make.leading.equalTo(view)
            make.trailing.equalTo(view)
            make.centerX.equalTo(view)
            make.top.equalTo(view.safeAreaLayoutGuide).inset(40)
            make.height.greaterThanOrEqualTo(view.snp.width).multipliedBy(4.0/3.0)
        }
        
        view.addSubview(hintLabel)
        hintLabel.snp.makeConstraints { make in
            make.leading.equalTo(view)
            make.trailing.equalTo(view)
            make.bottom.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(20)
        }
        
        view.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.leading.equalTo(view)
            make.trailing.equalTo(view.snp.centerX)
            make.height.equalTo(40)
            make.top.equalTo(previewView.snp.bottom).offset(10)
        }
        minusButton.addTarget(self, action: #selector(minusShutterScale), for: .touchUpInside)
        
        view.addSubview(plusButton)
        plusButton.snp.makeConstraints { make in
            make.leading.equalTo(view.snp.centerX)
            make.trailing.equalTo(view)
            make.height.equalTo(40)
            make.top.equalTo(previewView.snp.bottom).offset(10)
        }
        plusButton.addTarget(self, action: #selector(plusShutterScale), for: .touchUpInside)
        
        view.addSubview(lensPositionSlider)
        lensPositionSlider.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view)
            make.top.equalTo(plusButton.snp.bottom)
            make.height.equalTo(20)
        }
        lensPositionSlider.addTarget(self, action: #selector(lensPositionValueChanged(_:)), for: .valueChanged)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusTap(_:)))
        previewView.addGestureRecognizer(tapGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoomRecognizer(_:)))
        previewView.addGestureRecognizer(pinchGesture)
        
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.moonColor
            self.previewView.addSubview(self.spinner)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkCameraPermissions()
        checkPhotoPremissions()
        setupAndStartCaptureSession()
    }
    
    //MARK:- Permissions
    func checkCameraPermissions() {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch cameraAuthStatus {
        case .authorized:
            return
        case .denied:
            abort()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { (authorized) in
                if(!authorized){
                    abort()
                }
            })
        case .restricted:
            abort()
        @unknown default:
            fatalError()
        }
    }
    
    func checkPhotoPremissions() {
        let photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch photoAuthStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { authrized in
                if authrized != .authorized {
                    abort()
                }
            }
        case .restricted:
            abort()
        case .denied:
            abort()
        case .authorized:
            return
        case .limited:
            return
        @unknown default:
            fatalError()
        }
    }
    
    //MARK:- Camera Setup
    func setupAndStartCaptureSession(){
        sessionQueue.async{
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
        
        print("最小ISO值: \(minISO)")
        print("最大ISO值: \(maxISO)")
        print("\(captureDevice.activeFormat.maxExposureDuration)")
        print("\(captureDevice.activeFormat.minExposureDuration)")
        do {
            try captureDevice.lockForConfiguration()
            
            apertureFactor = captureDevice.lensAperture

            // 设置ISO值
            let desiredISO: Float = max(minISO, 50.0)
            iso = desiredISO
            // f/2.8 1/200 iso100
            let isoScale = desiredISO / 100.0
            let apertureScale = (2.8 * 2.8) / (apertureFactor * apertureFactor)
            let stop = Int32(200.0 * isoScale * apertureScale)
            
            let initExposureStop = findClosestNumber(to: stop, in: exposureStops)
            shutterScale = initExposureStop
            captureDevice.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: Int32(shutterScale)), iso: desiredISO, completionHandler: nil)
            
            captureDevice.unlockForConfiguration()
        } catch {
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
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
    }
    
    func setupPreviewView(){
        previewView.session = session
    }
    
    func updateHintLabel() {
        DispatchQueue.main.async {
            self.hintLabel.text = String(format: "iso:%.0f, position:%.4f, aperture:1/%.1f, shutter:1/%d", self.iso, self.lensPosition, self.apertureFactor, self.shutterScale)
        }
    }
    
    //MARK:- Actions
    @objc
    func captureImage(_ sender: UIButton?){
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
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
    func plusShutterScale() {
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex != 0 ? exposureStops[currentIndex - 1] : 100
            sessionQueue.async {
                self.update(shutterScale: nextStop)
            }
        }
    }
    
    @objc
    func minusShutterScale() {
        if let currentIndex = exposureStops.firstIndex(of: self.shutterScale) {
            let nextStop = currentIndex + 1 < exposureStops.count ? exposureStops[currentIndex + 1] : 2000
            sessionQueue.async {
                self.update(shutterScale: nextStop)
            }
        }
    }
    
    func update(shutterScale: Int32) {
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
    
    @objc func handlePinchToZoomRecognizer(_ gesture: UIPinchGestureRecognizer) {
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
}

class FocusView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderColor = UIColor.moonColor.cgColor
        layer.borderWidth = 1.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
