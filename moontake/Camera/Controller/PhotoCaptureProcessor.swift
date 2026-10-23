import AVFoundation
import Photos
import UIKit

final class PhotoCaptureProcessor: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    private let willCapturePhotoAnimation: () -> Void
    private let completionHandler: (PhotoCaptureProcessor, Error?) -> Void
    private let photoProcessingHandler: (Bool) -> Void
    private let liveRecordingHandler: (Bool) -> Void
    private let resources: LivePhotoResources?
    private let backgroundTask: LivePhotoBackgroundTask?
    private let targets: [ImageSaver.TargetType]
    private let toDatabase: Bool
    private let date = Date()
    private let locationName: String?
    private var photoData: Data?
    private var movieURL: URL?
    private var captureError: Error?
    private var finished = false
    var location: CLLocation?

    init(
        with settings: AVCapturePhotoSettings, resources: LivePhotoResources? = nil,
        backgroundTask: LivePhotoBackgroundTask? = nil,
        willCapturePhotoAnimation: @escaping () -> Void,
        completionHandler: @escaping (PhotoCaptureProcessor, Error?) -> Void,
        photoProcessingHandler: @escaping (Bool) -> Void,
        liveRecordingHandler: @escaping (Bool) -> Void = { _ in }
    ) {
        requestedPhotoSettings = settings
        self.resources = resources
        self.backgroundTask = backgroundTask
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.liveRecordingHandler = liveRecordingHandler
        // Snapshot user choices at shutter time, not several seconds later.
        switch Settings.shared.getSaveToAlbumSettings() {
        case .photoWithWatermark: targets = [.watermark]
        case .photoWithoutWatermark: targets = [.origin]
        case .both: targets = [.origin, .watermark]
        }
        toDatabase = Settings.shared.getAppAlbumSettings() == .enable
        locationName = CustomSettings.shared.locationName
    }
    private func finish(_ error: Error? = nil) {
        guard !finished else { return }
        finished = true
        liveRecordingHandler(false)
        photoProcessingHandler(false)
        // A failed first disk write keeps its resources in the retry error.
        if !(error is LivePhotoStagingFailure) { resources?.cleanUp() }
        backgroundTask?.end()
        completionHandler(self, error)
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor settings: AVCaptureResolvedPhotoSettings) {
        if requestedPhotoSettings.livePhotoMovieFileURL != nil { liveRecordingHandler(true) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor settings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        photoProcessingHandler(true)
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { captureError = error } else { photoData = photo.fileDataRepresentation() }
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt url: URL,
        resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        liveRecordingHandler(false)
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt url: URL,
        duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?
    ) {
        if let error {
            captureError = error
        } else if url.standardizedFileURL == resources?.movieURL.standardizedFileURL, duration.isNumeric,
            duration.seconds > 0
        {
            movieURL = url
        } else {
            captureError = ImageSaver.LivePhotoSaveError.missingMovie
        }
    }
    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishCaptureFor settings: AVCaptureResolvedPhotoSettings, error: Error?
    ) {
        if let error = error ?? captureError {
            finish(error)
            return
        }
        guard let photoData, let image = UIImage(data: photoData),
            let type = requestedPhotoSettings.processedFileType, let fileType = FileType.generate(by: type)
        else {
            finish(ImageSaver.LivePhotoSaveError.missingMovie)
            return
        }
        if requestedPhotoSettings.livePhotoMovieFileURL != nil {
            // Never silently save a static photo when Live was requested.
            guard let movieURL else {
                finish(ImageSaver.LivePhotoSaveError.missingMovie)
                return
            }
            ImageSaver.saveLivePhoto(
                photoData, movieURL: movieURL, targets: targets, fileType: fileType, location: location,
                width: Int(image.size.width), height: Int(image.size.height), date: date,
                customLocationName: locationName, toDatabase: toDatabase, backgroundTask: backgroundTask,
                captureResources: resources
            ) { [self] result in
                switch result {
                case .success: finish()
                case .failure(let error): finish(error)
                }
            }
        } else {
            ImageSaver.saveImage(
                photoData, targets: targets, fileType: fileType, location: location, width: Int(image.size.width),
                height: Int(image.size.height), date: date, customLocationName: locationName, toDatabase: toDatabase
            ) { [self] in finish() }
        }
    }
}
