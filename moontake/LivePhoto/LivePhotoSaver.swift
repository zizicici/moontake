import Foundation
import Photos
import UIKit

struct LivePhotoSaveFailure: LocalizedError {
  let jobID: UUID
  let underlying: Error
  var errorDescription: String? { String(localized: "live_photo.retained") }
}

/// If the very first disk write fails (for example, a full volume), retain the
/// compressed capture in memory and keep its movie alive for an explicit retry.
struct LivePhotoStagingFailure: LocalizedError {
  let id = UUID()
  let underlying: Error
  let retry: (@escaping (Result<Void, Error>) -> Void) -> Void
  var errorDescription: String? { String(localized: "live_photo.retention_failed") }
}

extension ImageSaver {
  enum LivePhotoSaveError: LocalizedError {
    case permission, missingMovie, library, localAlbum, busy
    var errorDescription: String? {
      switch self {
      case .permission: return String(localized: "live_photo.permission_failed")
      case .missingMovie: return String(localized: "live_photo.capture_failed")
      case .library: return String(localized: "live_photo.save_failed")
      case .localAlbum: return String(localized: "live_photo.local_save_failed")
      case .busy: return String(localized: "live_photo.save_busy")
      }
    }
  }

  static func saveLivePhoto(
    _ photoData: Data, movieURL: URL, targets: [TargetType], fileType: FileType,
    location: CLLocation?, width: Int, height: Int, date: Date, customLocationName: String?,
    toDatabase: Bool,
    backgroundTask: LivePhotoBackgroundTask? = nil,
    captureResources: LivePhotoResources? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let job = LivePhotoSaveJob(
      targets: targets, fileType: fileType, width: width, height: height,
      date: date, customLocationName: customLocationName, latitude: location?.coordinate.latitude,
      longitude: location?.coordinate.longitude, toDatabase: toDatabase)
    Task { @MainActor in
      let background = backgroundTask ?? LivePhotoBackgroundTask()
      defer {
        background.end()
        withExtendedLifetime(captureResources) {}
      }
      do {
        try await LivePhotoSaveService.shared.save(
          job, photoData: photoData, movieURL: movieURL,
          cancellation: background.cancellation)
        completion(.success(()))
      } catch let error as LivePhotoSaveFailure {
        completion(.failure(error))
      } catch {
        completion(
          .failure(
            LivePhotoStagingFailure(
              underlying: error,
              retry: { completion in
                saveLivePhoto(
                  photoData, movieURL: movieURL, targets: targets, fileType: fileType,
                  location: location, width: width, height: height, date: date,
                  customLocationName: customLocationName, toDatabase: toDatabase,
                  captureResources: captureResources, completion: completion)
              })))
      }
    }
  }
}

/// Only one movie is processed at a time, including recovery and album exports.
/// Pending jobs retain compressed files, not decoded frames.
actor LivePhotoSaveService {
  typealias Export = (
    LivePhotoSaveJob, Data, URL, LivePhotoCancellation,
    @escaping () async throws -> Void
  ) async throws -> Void
  static let shared = LivePhotoSaveService(store: .applicationStore)
  let store: LivePhotoSaveStore
  private let retainInAlbum: (LivePhotoSaveJob, Data, URL) throws -> Void
  private let export: Export
  private var activeID: UUID?

  init(
    store: LivePhotoSaveStore,
    retainInAlbum: @escaping (LivePhotoSaveJob, Data, URL) throws -> Void = LivePhotoSaveService
      .retainOriginal,
    export: @escaping Export = LivePhotoSaveService.exportToPhotos
  ) {
    self.store = store
    self.retainInAlbum = retainInAlbum
    self.export = export
  }

  func pending() -> [LivePhotoSaveJob] { store.pending().filter { $0.id != activeID } }

  func save(
    _ job: LivePhotoSaveJob, photoData: Data, movieURL: URL,
    cancellation: LivePhotoCancellation
  ) async throws {
    guard !job.targets.isEmpty, LivePhotoWatermark.identifier(in: photoData) != nil else {
      throw ImageSaver.LivePhotoSaveError.missingMovie
    }
    // Retain before permission checks, watermark rendering or Photos writes.
    try store.stage(job, photoData: photoData, movieURL: movieURL)
    try await retry(job.id, cancellation: cancellation)
  }

  func retry(_ id: UUID, cancellation: LivePhotoCancellation) async throws {
    do {
      guard activeID == nil else { throw ImageSaver.LivePhotoSaveError.busy }
      activeID = id
      defer { activeID = nil }
      var job = try store.load(id)
      if job.phase == .saved {
        try? store.remove(id)
        return
      }
      let data = try Data(contentsOf: store.photo(id), options: .mappedIfSafe)
      if job.toDatabase && !job.localAlbumSaved {
        try retainInAlbum(job, data, store.movie(id))
        job.localAlbumSaved = true
        try store.update(job)
      }
      try cancellation.check()
      do {
        try await export(job, data, store.movie(id), cancellation) {
          try await self.markSaving(id)
        }
      } catch {
        // A returned failure means Photos did not commit. Termination
        // before a result leaves .saving on disk and requires confirmation.
        job.phase = .prepared
        try? store.update(job)
        throw error
      }
      job.phase = .saved
      try store.update(job)
      // Cleanup failure must not cause another export on next launch.
      try? store.remove(id)
    } catch { throw LivePhotoSaveFailure(jobID: id, underlying: error) }
  }

  private func markSaving(_ id: UUID) throws {
    var job = try store.load(id)
    job.phase = .saving
    try store.update(job)
  }

  private static func retainOriginal(_ job: LivePhotoSaveJob, _ data: Data, _ movie: URL) throws {
    guard
      AlbumManager.shared.addImage(
        data: data, fileType: job.fileType, width: job.width, height: job.height,
        latitude: job.latitude, longitude: job.longitude, livePhotoMovieURL: movie,
        dataId: job.id.uuidString, date: job.date)
    else { throw ImageSaver.LivePhotoSaveError.localAlbum }
  }

  private static func exportToPhotos(
    _ job: LivePhotoSaveJob, _ photoData: Data, _ movieURL: URL,
    _ cancellation: LivePhotoCancellation, _ willCommit: @escaping () async throws -> Void
  ) async throws {
    try cancellation.check()
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else {
      throw ImageSaver.LivePhotoSaveError.permission
    }
    try cancellation.check()
    guard let identifier = LivePhotoWatermark.identifier(in: photoData) else {
      throw ImageSaver.LivePhotoSaveError.missingMovie
    }
    let work = try LivePhotoResources()
    defer { work.cleanUp() }
    var marked: LivePhotoWatermark.Still?
    let markedMovie = work.directory.appendingPathComponent("watermarked.mov")
    if job.targets.contains(.watermark) {
      await MoonManager.shared.prepare(at: job.date)
      try cancellation.check()
      let still = try LivePhotoWatermark.still(
        photoData, date: job.date,
        locationName: job.customLocationName, fileType: job.fileType)
      let foreground = await LivePhotoForegroundGuard(cancellation: cancellation)
      defer { withExtendedLifetime(foreground) {} }
      try await LivePhotoWatermark.movie(
        movieURL, to: markedMovie, still: still,
        identifier: identifier, cancellation: cancellation)
      marked = still
    }
    try cancellation.check()
    try await willCommit()
    let watermarked = marked
    // Once submitted, await the real result even if background time expires.
    // Termination leaves the durable .saving marker intact.
    try await PHPhotoLibrary.shared().performChanges {
      func create(_ data: Data, _ movie: URL, _ type: FileType) {
        let request = PHAssetCreationRequest.forAsset()
        request.location = job.location
        request.creationDate = job.date
        let photoOptions = PHAssetResourceCreationOptions()
        photoOptions.uniformTypeIdentifier = type.system.rawValue
        request.addResource(with: .photo, data: data, options: photoOptions)
        let movieOptions = PHAssetResourceCreationOptions()
        movieOptions.shouldMoveFile = false
        request.addResource(with: .pairedVideo, fileURL: movie, options: movieOptions)
      }
      if job.targets.contains(.origin) { create(photoData, movieURL, job.fileType) }
      if let watermarked { create(watermarked.data, markedMovie, watermarked.fileType) }
    }
  }
}
