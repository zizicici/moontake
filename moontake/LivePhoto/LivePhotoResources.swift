import Foundation

/// Owns only this capture's files. Keep alive through Photos' completion, since
/// its paired-video resource is read asynchronously from disk.
final class LivePhotoResources {
    let directory: URL
    let movieURL: URL
    init(parent: URL = FileManager.default.temporaryDirectory) throws {
        directory = parent.appendingPathComponent("LivePhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        movieURL = directory.appendingPathComponent("capture.mov")
    }
    /// Photos requires a recognized extension when constructing a Live Photo.
    /// The legacy album uses extensionless originals; link them without decoding
    /// or duplicating full-resolution image data in memory.
    func playbackStill(from original: URL, fileType: FileType) throws -> URL {
        let suffix: String
        switch fileType {
        case .jpeg: suffix = "jpg"
        case .heif: suffix = "heic"
        case .png: suffix = "png"
        }
        let target = directory.appendingPathComponent("photo.\(suffix)")
        do { try FileManager.default.linkItem(at: original, to: target) } catch {
            try FileManager.default.copyItem(at: original, to: target)
        }
        return target
    }
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    deinit { cleanUp() }
}
