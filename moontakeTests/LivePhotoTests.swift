import AVFoundation
import GRDB
import ImageIO
import Photos
import UIKit
import XCTest

@testable import moontake

final class LivePhotoTests: XCTestCase {
  func testTemporaryLiveExportPreservesWatermarkPairAndShareLifetime() async throws {
    let id = UUID().uuidString
    let data = try still(id: id, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    var capture: CapturedPhoto? = try await {
      let resources = try LivePhotoResources()
      try await movie(at: resources.movieURL, id: id, portrait: false, audio: false)
      return CapturedPhoto(data: data, fileType: .jpeg, width: 1600, height: 1200, date: Date(),
        location: nil, locationName: nil, targets: [.watermark], movieURL: resources.movieURL, resources: resources)
    }()
    weak var owner = capture?.resources
    let originalMovie = try XCTUnwrap(capture?.movieURL)
    var export: TemporaryPhotoExport? = try await TemporaryPhotoExport.prepare(
      try XCTUnwrap(capture), target: .watermark, cancellation: LivePhotoCancellation())
    XCTAssertEqual(LivePhotoWatermark.identifier(in: try XCTUnwrap(export?.data)), id)
    XCTAssertEqual(UIImage(data: try XCTUnwrap(export?.data))?.size.height, 1560)
    let stillURL = try XCTUnwrap(export?.photoURL)
    let movieURL = try XCTUnwrap(export?.movieURL)
    let ready = expectation(description: "Temporary watermarked Live Photo is playable")
    let request = PHLivePhoto.request(withResourceFileURLs: [stillURL, movieURL], placeholderImage: nil,
                                     targetSize: CGSize(width: 320, height: 312), contentMode: .aspectFit) { photo, info in
      guard (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
      XCTAssertNotNil(photo, "\(info)")
      ready.fulfill()
    }
    await fulfillment(of: [ready], timeout: 20)
    PHLivePhoto.cancelRequest(withRequestID: request)
    var providers = export?.itemProviders()
    XCTAssertEqual(providers?.count, 2, "Sharing must include both the finished still and its video")
    capture = nil; export = nil
    XCTAssertNotNil(owner)
    XCTAssertTrue(FileManager.default.fileExists(atPath: originalMovie.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: movieURL.path))
    providers = nil
    XCTAssertNil(owner)
    XCTAssertFalse(FileManager.default.fileExists(atPath: originalMovie.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: movieURL.path))
  }

  func testWatermarkedSilentLandscapePair() async throws {
    try await verifyPair(portrait: false, audio: false, fileType: .jpeg)
  }
  func testWatermarkedPortraitPairWithAudio() async throws {
    try await verifyPair(portrait: true, audio: true, fileType: .heif)
  }
  func testInvalidPairAndResourceCleanup() async throws {
    let resources = try LivePhotoResources()
    let id = UUID().uuidString
    let data = try still(id: id, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    let marked = try LivePhotoWatermark.still(
      data, date: Date(), locationName: nil, fileType: .jpeg)
    try await movie(at: resources.movieURL, id: id, portrait: false, audio: false)
    do {
      try await LivePhotoWatermark.movie(
        resources.movieURL, to: resources.directory.appendingPathComponent("bad.mov"),
        still: marked,
        identifier: "wrong-pair")
      XCTFail("Mismatched pairs must be rejected")
    } catch LivePhotoWatermark.Failure.invalidPair {}
    resources.cleanUp()
    resources.cleanUp()
    XCTAssertFalse(FileManager.default.fileExists(atPath: resources.directory.path))
    XCTAssertNil(LivePhotoWatermark.identifier(in: Data([0, 1, 2])))
  }

  @MainActor
  func testLiveAndSoundControlsLayoutAndInitialSilence() {
    let keys = [
      UserDefaults.Custom.LivePhoto.rawValue, UserDefaults.Custom.LivePhotoAudio.rawValue,
    ]
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    let location = CustomSettings.shared.locationName
    defer {
      for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
      CustomSettings.shared.locationName = location
    }
    keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    CustomSettings.shared.locationName = String(repeating: "Very long location 地点 ", count: 8)
    let camera = CameraViewController()
    camera.loadViewIfNeeded()  // No viewDidAppear: no camera, microphone or photo capture.
    func find(_ id: String, in view: UIView) -> UIButton? {
      if view.accessibilityIdentifier == id { return view as? UIButton }
      return view.subviews.compactMap { find(id, in: $0) }.first
    }
    let locationButton = find("camera.location", in: camera.view)!
    let locationNameButton = find("camera.locationName", in: camera.view)!
    let live = find("camera.livePhoto", in: camera.view)!
    let sound = find("camera.livePhotoAudio", in: camera.view)!
    for width in [320.0, 393.0, 852.0] {
      camera.view.frame = CGRect(x: 0, y: 0, width: width, height: 852)
      camera.view.layoutIfNeeded()
      XCTAssertLessThanOrEqual(locationButton.frame.maxX, locationNameButton.frame.minX)
      XCTAssertLessThanOrEqual(locationNameButton.frame.maxX, sound.frame.minX)
      XCTAssertLessThanOrEqual(sound.frame.maxX, live.frame.minX)
      XCTAssertEqual(locationButton.frame.width, 44, accuracy: 0.1)
      XCTAssertEqual(live.frame.width, 44, accuracy: 0.1)
      XCTAssertEqual(sound.frame.width, 0, accuracy: 0.1)
      XCTAssertEqual(live.frame.maxX, width - 6, accuracy: 0.1)
    }
    XCTAssertFalse(sound.isSelected)
    XCTAssertTrue(sound.isHidden, "The microphone is only shown when Live Photo is on")
    XCTAssertFalse(UserDefaults.standard.bool(forKey: keys[1]))
  }

  func testFullSizeThreeSecondWatermarkBudget() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let id = UUID().uuidString
    let data = try still(id: id, size: CGSize(width: 4032, height: 3024), type: .heif)
    try await movie(
      at: resources.movieURL, id: id, portrait: false, audio: false, width: 1920, height: 1440,
      frameCount: 90)
    let memory = MemorySampler()
    let start = Date()
    let marked = try LivePhotoWatermark.still(
      data, date: Date(), locationName: nil, fileType: .heif)
    print("LIVE_STILL peakMiB=\(Double(memory.stop())/1_048_576)")
    let movieMemory = MemorySampler()
    let output = resources.directory.appendingPathComponent("full-size.mov")
    try await LivePhotoWatermark.movie(
      resources.movieURL, to: output, still: marked, identifier: id)
    let duration = try await AVURLAsset(url: output).load(.duration)
    XCTAssertEqual(duration.seconds, 3, accuracy: 0.04)
    print(
      "LIVE_FULL_SIZE seconds=\(Date().timeIntervalSince(start)) baselineMiB=\(Double(memory.baseline)/1_048_576) peakMiB=\(Double(movieMemory.stop())/1_048_576)"
    )
  }

  /// Optional local regression data stays outside the repository and Photos library.
  func testLocalCameraPairReplay() async throws {
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(
        "LivePhotoRegression")
    let original = folder.appendingPathComponent("original.heic")
    guard FileManager.default.fileExists(atPath: original.path) else {
      throw XCTSkip("No local camera regression pair installed")
    }
    let data = try Data(contentsOf: original)
    let id = try XCTUnwrap(LivePhotoWatermark.identifier(in: data))
    let marked = try LivePhotoWatermark.still(
      data, date: Date(), locationName: nil, fileType: .heif)
    let output = folder.appendingPathComponent("watermarked.mov")
    try? FileManager.default.removeItem(at: output)
    try await LivePhotoWatermark.movie(
      folder.appendingPathComponent("original.mov"), to: output, still: marked, identifier: id)
    try marked.data.write(to: folder.appendingPathComponent("watermarked.heic"))
    let asset = AVURLAsset(url: output)
    let tracks = try await asset.load(.tracks)
    let video = try XCTUnwrap(tracks.first { $0.mediaType == .video })
    let size = try await video.load(.naturalSize)
    XCTAssertEqual(size.width, 1440)  // Full encoded width after portrait rotation; not the 1308 clean aperture.
    XCTAssertEqual(size.height, 2092)
    XCTAssertEqual(tracks.filter { $0.mediaType == .metadata }.count, 1)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    let frame = try generator.copyCGImage(
      at: CMTime(seconds: 1.483333, preferredTimescale: 600), actualTime: nil)
    try UIImage(cgImage: frame).pngData()!.write(
      to: folder.appendingPathComponent("watermarked-frame.png"))
    let ready = expectation(description: "Camera pair remains playable")
    let request = PHLivePhoto.request(
      withResourceFileURLs: [folder.appendingPathComponent("watermarked.heic"), output],
      placeholderImage: nil,
      targetSize: CGSize(width: 360, height: 540), contentMode: .aspectFit
    ) { photo, info in
      guard (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
      XCTAssertNotNil(photo, "\(info)")
      ready.fulfill()
    }
    await fulfillment(of: [ready], timeout: 20)
    PHLivePhoto.cancelRequest(withRequestID: request)
  }

  func testPhotosLibraryStoresBothTargetsAsLivePhotos() async throws {
    #if targetEnvironment(simulator)
      guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
        throw XCTSkip(
          "Grant Photos access to the simulator test app before running this integration test")
      }
      let resources = try LivePhotoResources()
      defer { resources.cleanUp() }
      let id = UUID().uuidString
      let data = try still(id: id, size: CGSize(width: 1600, height: 1200), type: .jpeg)
      try await movie(at: resources.movieURL, id: id, portrait: false, audio: false)
      // Use a unique historical timestamp to identify only this test's two assets.
      let date = Date(timeIntervalSince1970: 500_000_000 + Double.random(in: 1...1_000_000))
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        ImageSaver.saveLivePhoto(
          data, movieURL: resources.movieURL, targets: [.origin, .watermark], fileType: .jpeg,
          location: nil, width: 1600, height: 1200, date: date, customLocationName: nil,
          toDatabase: false
        ) { result in
          continuation.resume(with: result)
        }
      }
      let options = PHFetchOptions()
      options.predicate = NSPredicate(
        format: "creationDate >= %@ AND creationDate <= %@",
        date.addingTimeInterval(-0.01) as NSDate,
        date.addingTimeInterval(0.01) as NSDate)
      let assets = PHAsset.fetchAssets(with: .image, options: options)
      XCTAssertEqual(assets.count, 2)
      assets.enumerateObjects { asset, _, _ in
        XCTAssertTrue(asset.mediaSubtypes.contains(.photoLive))
        XCTAssertEqual(
          PHAssetResource.assetResources(for: asset).filter { $0.type == .pairedVideo }.count, 1)
      }
    // These two synthetic fixtures stay in the simulator for playback QA.
    // Deletion is intentionally outside the unit test: Photos requires a UI confirmation.

    #else
      throw XCTSkip("Synthetic library writes are confined to the simulator")
    #endif
  }

  func testCameraOrientationMetadataIsNormalized() throws {
    let id = UUID().uuidString
    let data = try still(id: id, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let encoded = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(encoded, AVFileType.jpg.rawValue as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(
      destination, source, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let marked = try LivePhotoWatermark.still(
      encoded as Data, date: Date(), locationName: nil, fileType: .jpeg)
    XCTAssertEqual(marked.originalSize, CGSize(width: 1200, height: 1600))
    XCTAssertEqual(marked.size, CGSize(width: 1200, height: 1960))
    let result = try XCTUnwrap(CGImageSourceCreateWithData(marked.data as CFData, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(result, 0, nil) as? [String: Any])
    XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
    XCTAssertEqual(LivePhotoWatermark.identifier(in: marked.data), id)
  }

  func testFailedWatermarkRetainsPairAndLocalAlbumBeforeExportThenRecovers() async throws {
    let storage = try LivePhotoResources()
    let capture = try LivePhotoResources()
    defer {
      storage.cleanUp()
      capture.cleanUp()
    }
    let store = LivePhotoSaveStore(root: storage.directory.appendingPathComponent("pending"))
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    let movieData = Data([1, 2, 3, 4])  // Persistence tests do not decode this resource.
    try movieData.write(to: capture.movieURL)
    let job = saveJob(toDatabase: true)
    var localSaves = 0
    let service = LivePhotoSaveService(
      store: store,
      retainInAlbum: { savedJob, savedData, movie in
        XCTAssertEqual(savedJob.id, job.id)
        XCTAssertEqual(savedJob.date, job.date)
        XCTAssertEqual(savedData, data)
        XCTAssertEqual(try Data(contentsOf: movie), movieData)
        localSaves += 1
      },
      export: { _, _, _, _, _ in
        XCTAssertEqual(localSaves, 1, "The local album must be saved before rendering or exporting")
        throw LivePhotoWatermark.Failure.video
      })
    do {
      try await service.save(
        job, photoData: data, movieURL: capture.movieURL, cancellation: LivePhotoCancellation())
      XCTFail("Expected a failed watermark")
    } catch let error as LivePhotoSaveFailure { XCTAssertEqual(error.jobID, job.id) }
    capture.cleanUp()  // The capture delegate may now dispose of its temporary files.
    XCTAssertEqual(try Data(contentsOf: store.photo(job.id)), data)
    XCTAssertEqual(try Data(contentsOf: store.movie(job.id)), movieData)
    XCTAssertTrue(try store.load(job.id).localAlbumSaved)
    let restarted = LivePhotoSaveService(
      store: store,
      retainInAlbum: { _, _, _ in
        XCTFail("A restart must not duplicate the local album entry")
      },
      export: { _, savedData, movie, _, willCommit in
        XCTAssertEqual(savedData, data)
        XCTAssertEqual(try Data(contentsOf: movie), movieData)
        try await willCommit()
        XCTAssertEqual(try store.load(job.id).phase, .saving)
      })
    let pending = await restarted.pending()
    XCTAssertEqual(pending.map(\.id), [job.id])
    try await restarted.retry(job.id, cancellation: LivePhotoCancellation())
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(job.id).path))
    XCTAssertEqual(localSaves, 1)
  }

  func testPhotosFailureKeepsPendingPairEvenWithAppAlbumDisabled() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let store = LivePhotoSaveStore(root: resources.directory.appendingPathComponent("pending"))
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    try Data([5, 6]).write(to: resources.movieURL)
    let job = saveJob(toDatabase: false)
    let service = LivePhotoSaveService(
      store: store,
      retainInAlbum: { _, _, _ in
        XCTFail("Disabled app album must remain disabled")
      },
      export: { _, _, _, _, willCommit in
        try await willCommit()
        XCTAssertEqual(try store.load(job.id).phase, .saving)
        throw ImageSaver.LivePhotoSaveError.library
      })
    do {
      try await service.save(
        job, photoData: data, movieURL: resources.movieURL, cancellation: LivePhotoCancellation())
      XCTFail("Expected Photos failure")
    } catch is LivePhotoSaveFailure {}
    XCTAssertEqual(try store.load(job.id).phase, .prepared)
    XCTAssertEqual(try Data(contentsOf: store.photo(job.id)), data)
    XCTAssertEqual(try Data(contentsOf: store.movie(job.id)), Data([5, 6]))
  }

  func testExpirationPreservesOriginalsWithoutStartingExport() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let store = LivePhotoSaveStore(root: resources.directory.appendingPathComponent("pending"))
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    try Data([7, 8]).write(to: resources.movieURL)
    let job = saveJob(toDatabase: false)
    let service = LivePhotoSaveService(
      store: store, export: { _, _, _, _, _ in XCTFail("Expired export started") })
    let cancellation = LivePhotoCancellation()
    cancellation.cancel()
    do {
      try await service.save(
        job, photoData: data, movieURL: resources.movieURL, cancellation: cancellation)
      XCTFail("Expected expiration")
    } catch let error as LivePhotoSaveFailure {
      XCTAssertTrue(error.underlying is CancellationError)
    }
    XCTAssertEqual(try Data(contentsOf: store.photo(job.id)), data)
    let pending = await service.pending()
    XCTAssertEqual(pending.map(\.id), [job.id])
  }

  func testInterruptedPhotosCommitIsNotAutomaticallyRepeated() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let store = LivePhotoSaveStore(root: resources.directory.appendingPathComponent("pending"))
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    try Data([9, 10]).write(to: resources.movieURL)
    var job = saveJob(toDatabase: false)
    try store.stage(job, photoData: data, movieURL: resources.movieURL)
    job.phase = .saving
    try store.update(job)
    let restarted = LivePhotoSaveService(
      store: store, export: { _, _, _, _, _ in XCTFail("Unconfirmed save was repeated") })
    let pending = await restarted.pending()
    XCTAssertEqual(pending.first?.phase, .saving)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.movie(job.id).path))
    job.phase = .saved  // Simulate a successful commit followed by interrupted cleanup.
    try store.update(job)
    let completed = await restarted.pending()
    XCTAssertTrue(completed.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(job.id).path))
  }

  func testBackgroundLeaseExpirationAndCompletionEndExactlyOnce() throws {
    var expiration: (() -> Void)?
    var ends = 0
    let background = LivePhotoBackgroundTask(
      begin: { callback in
        expiration = callback
        return UIBackgroundTaskIdentifier(rawValue: 42)
      }, end: { _ in ends += 1 })
    try background.cancellation.check()
    expiration?()
    XCTAssertThrowsError(try background.cancellation.check())
    background.end()
    expiration?()
    XCTAssertEqual(ends, 1)
    let synchronous = LivePhotoBackgroundTask(
      begin: { callback in
        callback()
        return UIBackgroundTaskIdentifier(rawValue: 43)
      }, end: { _ in ends += 1 })
    synchronous.end()
    XCTAssertEqual(ends, 2)
    XCTAssertThrowsError(try synchronous.cancellation.check())
  }

  func testExpiredMovieDoesNotCreateAnOutput() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    let marked = try LivePhotoWatermark.still(
      data, date: Date(), locationName: nil, fileType: .jpeg)
    let cancellation = LivePhotoCancellation()
    cancellation.cancel()
    let output = resources.directory.appendingPathComponent("expired.mov")
    do {
      try await LivePhotoWatermark.movie(
        resources.movieURL, to: output, still: marked,
        identifier: "unused", cancellation: cancellation)
      XCTFail("Expired conversion must stop before loading or allocating frames")
    } catch is CancellationError {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
  }

  func testLocalAlbumRetryAfterCommitUsesTheSameEntryAndCaptureDate() throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    try Data([11, 12]).write(to: resources.movieURL)
    let job = saveJob(toDatabase: true)
    func entries() throws -> [ImageInfo] {
      try XCTUnwrap(AppDatabase.shared.reader).read { db in
        try ImageInfo.filter(Column("data_id") == job.id.uuidString).fetchAll(db)
      }
    }
    defer {
      for info in (try? entries()) ?? [] {
        _ = AppDatabase.shared.delete(imageInfo: info)
        for url in [info.originURL, info.thumbnailURL, info.pairedVideoURL].compactMap({ $0 }) {
          try? FileManager.default.removeItem(at: url)
        }
      }
    }
    for _ in 0..<2 {
      XCTAssertTrue(
        AlbumManager.shared.addImage(
          data: data, fileType: job.fileType,
          width: job.width, height: job.height, latitude: nil, longitude: nil,
          livePhotoMovieURL: resources.movieURL, dataId: job.id.uuidString, date: job.date))
    }
    let saved = try entries()
    XCTAssertEqual(saved.count, 1)
    XCTAssertEqual(saved.first?.creationDate, job.date)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(saved.first?.pairedVideoURL)), Data([11, 12]))
  }

  func testDisconnectedDatabaseCannotReportSuccessfulRetention() throws {
    let database = try AppDatabase(DatabaseQueue())
    database.disconnect()
    let info = ImageInfo(
      dataId: UUID().uuidString, fileType: .jpeg, width: 10, height: 10,
      latitude: nil, longitude: nil)
    XCTAssertFalse(database.add(imageInfo: info))
    XCTAssertFalse(database.containsImage(dataId: info.dataId))
  }

  func testConcurrentSavesRetainBothPairsButRunOnlyOneExporter() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let store = LivePhotoSaveStore(root: resources.directory.appendingPathComponent("pending"))
    let data = try still(
      id: UUID().uuidString, size: CGSize(width: 1600, height: 1200), type: .jpeg)
    try Data([13, 14]).write(to: resources.movieURL)
    let first = saveJob(toDatabase: false)
    let second = saveJob(toDatabase: false)
    let entered = expectation(description: "First exporter is running")
    let gate = LivePhotoTestGate()
    let service = LivePhotoSaveService(
      store: store,
      export: { job, _, _, _, commit in
        if job.id == first.id { entered.fulfill() }
        await gate.wait()
        try await commit()
      })
    let running = Task {
      try await service.save(
        first, photoData: data, movieURL: resources.movieURL,
        cancellation: LivePhotoCancellation())
    }
    await fulfillment(of: [entered], timeout: 5)
    do {
      try await service.save(
        second, photoData: data, movieURL: resources.movieURL,
        cancellation: LivePhotoCancellation())
      XCTFail("Concurrent movie processing should be deferred")
    } catch let error as LivePhotoSaveFailure {
      XCTAssertEqual(error.jobID, second.id)
    }
    let pending = await service.pending()
    XCTAssertEqual(pending.map(\.id), [second.id])
    XCTAssertEqual(try Data(contentsOf: store.photo(second.id)), data)
    await gate.open()
    try await running.value
    try await service.retry(second.id, cancellation: LivePhotoCancellation())
    let remaining = await service.pending()
    XCTAssertTrue(remaining.isEmpty)
  }

  @MainActor
  func testGPUConversionStopsBeforeBackgroundAndOnBackgroundStart() throws {
    let center = NotificationCenter()
    let cancellation = LivePhotoCancellation()
    let foreground = LivePhotoForegroundGuard(
      cancellation: cancellation, center: center, isBackground: false)
    defer { withExtendedLifetime(foreground) {} }
    try cancellation.check()
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertThrowsError(try cancellation.check())
    let alreadyBackground = LivePhotoCancellation()
    let background = LivePhotoForegroundGuard(
      cancellation: alreadyBackground, center: center, isBackground: true)
    defer { withExtendedLifetime(background) {} }
    XCTAssertThrowsError(try alreadyBackground.check())
  }

  func testMovieCancellationRemovesPartialOutputAndKeepsOriginal() async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let id = UUID().uuidString
    let data = try still(id: id, size: CGSize(width: 4032, height: 3024), type: .heif)
    let marked = try LivePhotoWatermark.still(data, date: Date(), locationName: nil, fileType: .heif)
    try await movie(at: resources.movieURL, id: id, portrait: false, audio: false,
                    width: 1920, height: 1440, frameCount: 180)
    let output = resources.directory.appendingPathComponent("cancelled.mov")
    let cancellation = LivePhotoCancellation()
    let interrupt = Task {
      try await Task.sleep(nanoseconds: 50_000_000)
      cancellation.cancel()
    }
    defer { interrupt.cancel() }
    do {
      try await LivePhotoWatermark.movie(resources.movieURL, to: output, still: marked,
                                         identifier: id, cancellation: cancellation)
      XCTFail("The interrupted conversion must not publish a partial movie")
    } catch is CancellationError {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: resources.movieURL.path))
  }

  private func saveJob(toDatabase: Bool) -> LivePhotoSaveJob {
    LivePhotoSaveJob(
      targets: [.origin, .watermark], fileType: .jpeg, width: 1600, height: 1200,
      date: Date(timeIntervalSince1970: 1_792_627_200), customLocationName: "Test", latitude: nil,
      longitude: nil, toDatabase: toDatabase)
  }

  private func verifyPair(portrait: Bool, audio: Bool, fileType: FileType) async throws {
    let resources = try LivePhotoResources()
    defer { resources.cleanUp() }
    let id = UUID().uuidString
    let size = portrait ? CGSize(width: 1200, height: 1600) : CGSize(width: 1600, height: 1200)
    let data = try still(id: id, size: size, type: fileType)
    let date = Date(timeIntervalSince1970: 1_792_627_200)
    await MoonManager.shared.prepare(at: date)
    let marked = try LivePhotoWatermark.still(
      data, date: date, locationName: "Test", fileType: fileType)
    XCTAssertEqual(LivePhotoWatermark.identifier(in: marked.data), id)
    XCTAssertEqual(marked.size, CGSize(width: size.width, height: size.height + 360))
    try await movie(at: resources.movieURL, id: id, portrait: portrait, audio: audio)
    let output = resources.directory.appendingPathComponent("watermarked.mov")
    let start = Date()
    try await LivePhotoWatermark.movie(
      resources.movieURL, to: output, still: marked, identifier: id)
    print(
      "LIVE_WATERMARK portrait=\(portrait) audio=\(audio) seconds=\(Date().timeIntervalSince(start))"
    )
    let asset = AVURLAsset(url: output)
    let tracks = try await asset.load(.tracks)
    XCTAssertEqual(tracks.filter { $0.mediaType == .audio }.count, audio ? 1 : 0)
    let video = try XCTUnwrap(tracks.first { $0.mediaType == .video })
    let dimensions = try await video.load(.naturalSize)
    XCTAssertEqual(
      dimensions.width / dimensions.height, marked.size.width / marked.size.height, accuracy: 0.006)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 1, accuracy: 0.05)
    let metadataTrack = try XCTUnwrap(tracks.first { $0.mediaType == .metadata })
    let reader = try AVAssetReader(asset: asset)
    let outputMetadata = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
    reader.add(outputMetadata)
    let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: outputMetadata)
    XCTAssertTrue(reader.startReading())
    let group = try XCTUnwrap(adaptor.nextTimedMetadataGroup())
    XCTAssertEqual(group.timeRange.start.seconds, 0.5, accuracy: 0.001)
    XCTAssertEqual(
      group.items.compactMap { $0.identifier?.rawValue },
      [LivePhotoWatermark.stillImageTimeIdentifier])
    XCTAssertEqual(tracks.filter { $0.mediaType == .metadata }.count, 1)
    reader.cancelReading()
    // Decode a frame to verify orientation and bottom footer, not just metadata.
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    let frame = try generator.copyCGImage(at: CMTime(value: 15, timescale: 30), actualTime: nil)
    let pixels = rgba(frame)
    let topLeft = pixel(pixels, width: frame.width, x: frame.width / 4, y: 20)
    let topRight = pixel(pixels, width: frame.width, x: frame.width * 3 / 4, y: 20)
    let footer = pixel(pixels, width: frame.width, x: 3, y: frame.height - 3)
    XCTAssertGreaterThan(topLeft.0, topLeft.2 + 80, "Red left side must remain upright")
    XCTAssertGreaterThan(topRight.2, topRight.0 + 80, "Blue right side must remain upright")
    XCTAssertGreaterThan(footer.0, 230)
    XCTAssertGreaterThan(footer.1, 230)
    XCTAssertGreaterThan(footer.2, 230)
    let attachment = XCTAttachment(image: UIImage(cgImage: frame))
    attachment.name = "Live watermarked frame portrait=\(portrait)"
    attachment.lifetime = .keepAlways
    add(attachment)
    // Extensionless originals are how the existing app album stores its stills.
    let stillURL = resources.directory.appendingPathComponent("original")
    try marked.data.write(to: stillURL)
    let namedPhoto = try resources.playbackStill(from: stillURL, fileType: fileType)
    let done = expectation(description: "Photos accepts the watermarked pair")
    let request = PHLivePhoto.request(
      withResourceFileURLs: [namedPhoto, output], placeholderImage: nil,
      targetSize: CGSize(width: 320, height: 480), contentMode: .aspectFit
    ) { photo, info in
      guard (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
      XCTAssertNotNil(photo, "\(info)")
      done.fulfill()
    }
    await fulfillment(of: [done], timeout: 20)
    PHLivePhoto.cancelRequest(withRequestID: request)
  }

  private func still(id: String, size: CGSize, type: FileType) throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      UIColor.blue.setFill()
      context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
    }
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(data, type.system.rawValue as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, image.cgImage!,
      [kCGImagePropertyMakerAppleDictionary: ["17": id]] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func movie(
    at url: URL, id: String, portrait: Bool, audio: Bool, width: Int = 320, height: Int = 240,
    frameCount: Int = 30
  ) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let identifier = AVMutableMetadataItem()
    identifier.identifier = .quickTimeMetadataContentIdentifier
    identifier.value = id as NSString
    identifier.dataType = kCMMetadataBaseDataType_UTF8 as String
    writer.metadata = [identifier]
    let video = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCleanApertureKey: [
          AVVideoCleanApertureWidthKey: Double(width) * 0.9,
          AVVideoCleanApertureHeightKey: Double(height) * 0.9,
          AVVideoCleanApertureHorizontalOffsetKey: 0, AVVideoCleanApertureVerticalOffsetKey: 0,
        ],
      ])
    if portrait {
      video.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
    }
    writer.add(video)
    let pixels = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: video,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ])
    var format: CMMetadataFormatDescription?
    let spec = [
      kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
        "mdta/com.apple.quicktime.still-image-time",
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
        kCMMetadataBaseDataType_SInt8
        as String,
    ]
    XCTAssertEqual(
      CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
        allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
        metadataSpecifications: [
          spec,
          [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
              kCMMetadataIdentifier_QuickTimeMetadataVideoOrientation as String,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
              kCMMetadataBaseDataType_SInt16 as String,
          ],
          [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
              kCMMetadataIdentifier_QuickTimeMetadataLivePhotoStillImageTransform as String,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
              kCMMetadataBaseDataType_PerspectiveTransformF64 as String,
          ],
        ] as CFArray, formatDescriptionOut: &format), noErr)
    let metadata = AVAssetWriterInput(
      mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
    writer.add(metadata)
    let metaAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)
    var audioInput: AVAssetWriterInput?
    if audio {
      let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64000,
        ])
      writer.add(input)
      audioInput = input
    }
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    let time = AVMutableMetadataItem()
    time.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.still-image-time")
    time.dataType = kCMMetadataBaseDataType_SInt8 as String
    time.value = 0 as NSNumber
    let orientation = AVMutableMetadataItem()
    orientation.identifier = AVMetadataIdentifier(
      rawValue: kCMMetadataIdentifier_QuickTimeMetadataVideoOrientation as String)
    orientation.value = NSNumber(value: portrait ? 6 : 1)
    orientation.dataType = kCMMetadataBaseDataType_SInt16 as String
    let transform = AVMutableMetadataItem()
    transform.identifier = AVMetadataIdentifier(
      rawValue: kCMMetadataIdentifier_QuickTimeMetadataLivePhotoStillImageTransform as String)
    transform.value = [1.1, 0, 0, 0, 1.1, 0, 0, 0, 1] as NSArray
    transform.dataType = kCMMetadataBaseDataType_PerspectiveTransformF64 as String
    XCTAssertTrue(
      metaAdaptor.append(
        AVTimedMetadataGroup(
          items: [time, orientation, transform],
          timeRange: CMTimeRange(
            start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 1, timescale: 30)))))
    metadata.markAsFinished()
    if let audioInput {
      let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
      var block: CMBlockBuffer?
      XCTAssertEqual(
        CMBlockBufferCreateWithMemoryBlock(
          allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 44100 * 4,
          blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
          dataLength: 44100 * 4,
          flags: 0, blockBufferOut: &block), noErr)
      let samples = (0..<44100).map { Float(sin(Double($0) * 2 * Double.pi * 440 / 44100) * 0.1) }
      samples.withUnsafeBytes { bytes in
        _ = CMBlockBufferReplaceDataBytes(
          with: bytes.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0,
          dataLength: bytes.count)
      }
      var sample: CMSampleBuffer?
      var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 44100), presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid)
      var sampleSize = 4
      XCTAssertEqual(
        CMSampleBufferCreateReady(
          allocator: kCFAllocatorDefault, dataBuffer: block,
          formatDescription: format.formatDescription,
          sampleCount: 44100, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
          sampleSizeEntryCount: 1,
          sampleSizeArray: &sampleSize, sampleBufferOut: &sample), noErr)
      XCTAssertTrue(audioInput.append(sample!), "\(String(describing:writer.error))")
      audioInput.markAsFinished()
    }
    // Reuse one immutable source frame; fixture generation isn't the measured work.
    var buffer: CVPixelBuffer?
    XCTAssertEqual(
      CVPixelBufferPoolCreatePixelBuffer(nil, pixels.pixelBufferPool!, &buffer), kCVReturnSuccess)
    CVPixelBufferLockBaseAddress(buffer!, [])
    let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer!), width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue)!
    context.setFillColor(UIColor.blue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(UIColor.red.cgColor)
    context.fill(
      portrait
        ? CGRect(x: 0, y: 0, width: width, height: height / 2)
        : CGRect(x: 0, y: 0, width: width / 2, height: height))
    CVPixelBufferUnlockBaseAddress(buffer!, [])
    for index in 0..<frameCount {
      while !video.isReadyForMoreMediaData {
        if writer.status == .failed { throw writer.error! }
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      XCTAssertTrue(
        pixels.append(buffer!, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
    }
    video.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed, "\(String(describing:writer.error))")
  }
  private func rgba(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }
  private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (Int, Int, Int) {
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
  }
}

private actor LivePhotoTestGate {
  private var isOpen = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

private final class MemorySampler {
  let baseline: UInt64
  private let lock = NSLock()
  private var peak: UInt64
  private let timer = DispatchSource.makeTimerSource(
    queue: DispatchQueue(label: "livePhoto.test.memory", qos: .utility))
  init() {
    baseline = Self.footprint()
    peak = baseline
    timer.schedule(deadline: .now(), repeating: .milliseconds(10))
    timer.setEventHandler { [weak self] in self?.sample() }
    timer.resume()
  }
  deinit { timer.cancel() }
  private func sample() {
    let value = Self.footprint()
    lock.lock()
    peak = max(peak, value)
    lock.unlock()
  }
  func stop() -> UInt64 {
    timer.cancel()
    sample()
    lock.lock()
    defer { lock.unlock() }
    return peak
  }
  private static func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
    let capacity = Int(count)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
  }
}
