import Photos
import UIKit

/// Owns the compressed capture until a destination or the temporary detail page takes it.
struct CapturedPhoto {
    let data: Data
    let fileType: FileType
    let width: Int
    let height: Int
    let date: Date
    let location: CLLocation?
    let locationName: String?
    let targets: [ImageSaver.TargetType]
    let movieURL: URL?
    let resources: LivePhotoResources?
}

struct CaptureSaveOutcome {
    let localSaved: Bool
    let photosSaved: Bool
    var needsTemporaryDetail: Bool { !localSaved && !photosSaved }
}

/// Local storage never depends on Photos permission or on a successful Photos transaction.
struct CapturePhotoSaver {
    var authorization: () async -> PHAuthorizationStatus = {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .notDetermined ? await PHPhotoLibrary.requestAuthorization(for: .addOnly) : status
    }
    var saveLocal: (CapturedPhoto) -> Bool = { photo in
        AlbumManager.shared.addImage(
            data: photo.data, fileType: photo.fileType, width: photo.width, height: photo.height,
            latitude: photo.location?.coordinate.latitude, longitude: photo.location?.coordinate.longitude,
            livePhotoMovieURL: photo.movieURL, date: photo.date)
    }
    var savePhotos: (CapturedPhoto, LivePhotoBackgroundTask?) async throws -> Void = { photo, backgroundTask in
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: (Result<Void, Error>) -> Void = { continuation.resume(with: $0) }
            if let movie = photo.movieURL {
                ImageSaver.saveLivePhoto(
                    photo.data, movieURL: movie, targets: photo.targets, fileType: photo.fileType,
                    location: photo.location, width: photo.width, height: photo.height, date: photo.date,
                    customLocationName: photo.locationName, toDatabase: false, backgroundTask: backgroundTask,
                    captureResources: photo.resources, completion: completion)
            } else {
                ImageSaver.saveImage(
                    photo.data, targets: photo.targets, fileType: photo.fileType, location: photo.location,
                    width: photo.width, height: photo.height, date: photo.date,
                    customLocationName: photo.locationName, toDatabase: false, completion: completion)
            }
        }
    }

    func save(_ photo: CapturedPhoto, toLocalAlbum: Bool,
              backgroundTask: LivePhotoBackgroundTask? = nil) async -> CaptureSaveOutcome {
        let localSaved = toLocalAlbum && saveLocal(photo)
        let status = await authorization()
        var photosSaved = false
        if status == .authorized || status == .limited {
            do {
                try await savePhotos(photo, backgroundTask)
                photosSaved = true
            } catch {
                // The caller still owns the original capture, including the Live movie.
                // If neither destination succeeded, show it instead of discarding it.
            }
        }
        return CaptureSaveOutcome(localSaved: localSaved, photosSaved: photosSaved)
    }
}
