import CoreLocation
import Foundation

struct LivePhotoSaveJob: Codable, Identifiable {
  enum Phase: String, Codable { case prepared, saving, saved }
  var id = UUID()
  let targets: [ImageSaver.TargetType]
  let fileType: FileType
  let width: Int
  let height: Int
  let date: Date
  let customLocationName: String?
  let latitude: Double?
  let longitude: Double?
  let toDatabase: Bool
  var localAlbumSaved = false
  var phase = Phase.prepared

  var location: CLLocation? {
    guard let latitude, let longitude else { return nil }
    return CLLocation(latitude: latitude, longitude: longitude)
  }
}

/// All access is serialized by LivePhotoSaveService. A manifest is committed only
/// after both originals exist; interrupted Photos transactions remain ambiguous.
struct LivePhotoSaveStore {
  let root: URL

  static var applicationStore: Self {
    Self(
      root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PendingLivePhotos", isDirectory: true))
  }

  func directory(_ id: UUID) -> URL {
    root.appendingPathComponent(id.uuidString, isDirectory: true)
  }
  func photo(_ id: UUID) -> URL { directory(id).appendingPathComponent("photo") }
  func movie(_ id: UUID) -> URL { directory(id).appendingPathComponent("capture.mov") }

  func stage(_ job: LivePhotoSaveJob, photoData: Data, movieURL: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory(job.id), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    do {
      try photoData.write(
        to: photo(job.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      try Self.linkOrCopy(from: movieURL, to: movie(job.id))
      try manager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: movie(job.id).path)
      try update(job)
    } catch {
      // The caller still owns both originals when staging fails.
      try? manager.removeItem(at: directory(job.id))
      throw error
    }
  }

  func update(_ job: LivePhotoSaveJob) throws {
    try JSONEncoder().encode(job).write(
      to: directory(job.id).appendingPathComponent("job.json"),
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func load(_ id: UUID) throws -> LivePhotoSaveJob {
    let job = try JSONDecoder().decode(
      LivePhotoSaveJob.self,
      from: Data(contentsOf: directory(id).appendingPathComponent("job.json")))
    guard job.id == id else { throw CocoaError(.fileReadCorruptFile) }
    return job
  }

  func pending() -> [LivePhotoSaveJob] {
    let directories =
      (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return directories.compactMap { url -> LivePhotoSaveJob? in
      guard let id = UUID(uuidString: url.lastPathComponent), let job = try? load(id) else {
        return nil
      }
      if job.phase == .saved {
        try? remove(id)
        return nil
      }
      return job
    }.sorted { $0.date < $1.date }
  }

  func remove(_ id: UUID) throws { try FileManager.default.removeItem(at: directory(id)) }

  static func linkOrCopy(from source: URL, to destination: URL) throws {
    do { try FileManager.default.linkItem(at: source, to: destination) } catch {
      try FileManager.default.copyItem(at: source, to: destination)
    }
  }
}
