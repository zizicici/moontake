import UIKit
import UniformTypeIdentifiers

/// Keeps only compressed photos and movie files; no full-resolution video frames are retained.
final class TemporaryPhotoExport {
    let data: Data
    let fileType: FileType
    let photoURL: URL?
    let movieURL: URL?
    private let resources: LivePhotoResources?
    private let source: CapturedPhoto

    private init(data: Data, fileType: FileType, photoURL: URL?, movieURL: URL?,
                 resources: LivePhotoResources?, source: CapturedPhoto) {
        self.data = data; self.fileType = fileType; self.photoURL = photoURL; self.movieURL = movieURL
        self.resources = resources; self.source = source
    }

    static func prepare(_ photo: CapturedPhoto, target: ImageSaver.TargetType,
                        cancellation: LivePhotoCancellation) async throws -> TemporaryPhotoExport {
        try cancellation.check()
        let work = try? LivePhotoResources()
        var data = photo.data
        var type = photo.fileType
        var movie = photo.movieURL
        if target == .watermark {
            await MoonManager.shared.prepare(at: photo.date)
            try cancellation.check()
            if let sourceMovie = movie {
                guard let work else { throw CocoaError(.fileWriteOutOfSpace) }
                guard let identifier = LivePhotoWatermark.identifier(in: photo.data) else {
                    throw ImageSaver.LivePhotoSaveError.missingMovie
                }
                let still = try LivePhotoWatermark.still(
                    photo.data, date: photo.date, locationName: photo.locationName, fileType: photo.fileType)
                let destination = work.directory.appendingPathComponent("moontake.mov")
                let foreground = await LivePhotoForegroundGuard(cancellation: cancellation)
                defer { withExtendedLifetime(foreground) {} }
                try await LivePhotoWatermark.movie(sourceMovie, to: destination, still: still,
                                                   identifier: identifier, cancellation: cancellation)
                data = still.data; type = still.fileType; movie = destination
            } else {
                guard let marked = ImageSaver.addWaterMark(for: photo.data, date: photo.date,
                                                           customLocationName: photo.locationName) else {
                    throw ImageSaver.SaveError.rendering
                }
                data = marked; type = ImageSaver.encodedFileType(marked)
            }
        }
        try cancellation.check()
        let suffix = type == .heif ? "heic" : type == .png ? "png" : "jpg"
        var stillURL = work?.directory.appendingPathComponent("moontake.\(suffix)")
        if let url = stillURL {
            do { try data.write(to: url, options: .atomic) }
            catch { stillURL = nil } // Still photos can also be shared directly from compressed data.
        }
        return TemporaryPhotoExport(data: data, fileType: type, photoURL: stillURL, movieURL: movie,
                                    resources: work, source: photo)
    }

    func itemProviders() -> [NSItemProvider] {
        let image = NSItemProvider()
        image.suggestedName = "moontake.\(fileType == .heif ? "heic" : fileType == .png ? "png" : "jpg")"
        image.registerDataRepresentation(forTypeIdentifier: fileType.system.rawValue, visibility: .all) {
            [self] completion in
            completion(data, nil)
            return nil
        }
        var providers = [image]
        if let movieURL {
            let movie = NSItemProvider()
            movie.suggestedName = "moontake.mov"
            movie.registerFileRepresentation(forTypeIdentifier: UTType.quickTimeMovie.identifier,
                                             fileOptions: [], visibility: .all) { [self] completion in
                withExtendedLifetime(self) { completion(movieURL, false, nil) }
                return nil
            }
            providers.append(movie)
        }
        return providers
    }
}
