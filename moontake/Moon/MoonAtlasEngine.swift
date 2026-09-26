import Foundation
import UIKit
import ImageIO
import JavaScriptCore
import SkyKit

struct MoonAtlasFeature: Decodable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let diameterKm: Double
    let type: String
    let source: URL
    let reference: MoonAtlasFeatureReference?
    let readingSources: [MoonAtlasReadingSource]

    var displayName: String {
        guard type == "crater" else { return labelName }
        return String(format: String(localized: "atlas.crater.name"), labelName)
    }

    var labelName: String {
        Bundle.main.localizedString(forKey: "atlas.feature.\(id).label", value: name, table: nil)
    }

    /// Article keys are maintained explicitly in the string catalog so editors
    /// can verify every language against the recorded scientific sources.
    func articleText(_ section: MoonAtlasArticleSection, bundle: Bundle = .main) -> String {
        let key = "atlas.feature.\(id).\(section.rawValue)"
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Conservative display cutoffs in analysis pixels, independent of digital
    /// zoom. These are visibility heuristics, not individual-feature detections.
    func isVisible(moonRadius: Double, emission: Double, incidence: Double) -> Bool {
        guard emission > 0.1, incidence > 0.08 else { return false }
        switch type {
        case "crater": return diameterKm / 3474.8 * moonRadius * 2 * sqrt(emission) >= 2
        case "mountain": return moonRadius * 2 >= 180 && emission > 0.2 && incidence < 0.75
        default: return true
        }
    }

    var coordinateText: String {
        String(format: "%.1f°%@  %.1f°%@", abs(latitude), latitude < 0 ? "S" : "N",
               abs(longitude), longitude < 0 ? "W" : "E")
    }
}

enum MoonAtlasArticleSection: String, CaseIterable {
    case naming, story, observation
}

struct MoonAtlasReadingSource: Decodable {
    let url: URL
    let titleKey: String

    var displayTitle: String {
        Bundle.main.localizedString(forKey: titleKey, value: nil, table: nil)
    }
}

struct MoonAtlasFeatureReference: Decodable {
    let credit: String
    let source: URL
}

struct MoonAtlasFit: Decodable, Equatable {
    var x: Double
    var y: Double
    var radius: Double
    var rotation: Double
    var mirror: Bool?
    var accepted: Bool?
    var reason: String?
}

struct MoonAtlasPhoto {
    let image: UIImage
    let captureDate: Date?
    let latitude: Double?
    let longitude: Double?
}

struct MoonAtlasResult {
    let fit: MoonAtlasFit
    let surface: MoonSurface
    let reference: UIImage
    let features: [MoonAtlasFeature]
}

enum MoonAtlasError: LocalizedError {
    case unreadablePhoto, unavailableGeometry, processing
    var errorDescription: String? {
        switch self {
        case .unreadablePhoto: return String(localized: "atlas.error.photo")
        case .unavailableGeometry: return String(localized: "atlas.error.date")
        case .processing: return String(localized: "atlas.error.processing")
        }
    }
}

/// Runs decoding and the shared registration core off the main actor. JavaScriptCore
/// is just an in-process calculation engine here; no web view or network is involved.
actor MoonAtlasEngine {
    func load(_ info: ImageInfo) throws -> MoonAtlasPhoto {
        guard let url = info.originURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw MoonAtlasError.unreadablePhoto }
        return MoonAtlasPhoto(image: UIImage(cgImage: image),
                              captureDate: Self.captureDate(source: source, fallback: info.creationDate),
                              latitude: info.latitude, longitude: info.longitude)
    }

    func recognize(_ photo: MoonAtlasPhoto, at date: Date, mirror: Bool = false) throws -> MoonAtlasResult {
        try autoreleasepool {
            var observer: MoonSurfaceObserver = .geocentric
            if let lat = photo.latitude, let lon = photo.longitude, lat.isFinite, lon.isFinite,
               abs(lat) <= 90, abs(lon) <= 180 { observer = .earth(latitude: lat, longitude: lon) }
            guard let surface = Moon.surface(at: date, observer: observer, north: .icrf) else {
                throw MoonAtlasError.unavailableGeometry
            }
            guard let root = Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources"),
                  let context = JSContext(), let image = photo.image.cgImage,
                  let textureSource = CGImageSourceCreateWithURL(root.appendingPathComponent("assets/moon-color.jpg") as CFURL, nil),
                  let textureImage = CGImageSourceCreateImageAtIndex(textureSource, 0, nil) else { throw MoonAtlasError.processing }
            let code = try String(contentsOf: root.appendingPathComponent("moon-core.js"), encoding: .utf8)
            context.evaluateScript(code)
            guard context.exception == nil, let core = context.objectForKeyedSubscript("MoonAtlasCore"), !core.isUndefined else {
                throw MoonAtlasError.processing
            }
            let texture: [String: Any] = ["data": try Self.pixels(textureImage, in: context), "width": textureImage.width, "height": textureImage.height]
            let matrix = surface.bodyToView
            let geometry: [String: Any] = [
                "bodyToView": (0..<3).map { row in (0..<3).map { column in matrix[column][row] } },
                "sunDirection": [surface.sunDirection.x, surface.sunDirection.y, surface.sunDirection.z]
            ]
            guard let gray = core.invokeMethod("gray", withArguments: [try Self.pixels(image, in: context)]),
                  let model = core.invokeMethod("renderMoon", withArguments: [texture, geometry, 160]),
                  let disc = core.invokeMethod("detectDisc", withArguments: [gray, image.width, image.height]) else {
                throw MoonAtlasError.processing
            }
            var fit = MoonAtlasFit(x: Double(image.width) / 2, y: Double(image.height) / 2,
                                   radius: Double(min(image.width, image.height)) * 0.28,
                                   rotation: 0, mirror: mirror, accepted: false, reason: "disc")
            if !disc.isNull, !disc.isUndefined {
                guard let matched = core.invokeMethod("registerMoon", withArguments: [gray, image.width, image.height, disc, model, mirror]),
                      let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [matched])?.toString(),
                      let data = json.data(using: .utf8) else { throw MoonAtlasError.processing }
                fit = try JSONDecoder().decode(MoonAtlasFit.self, from: data)
            }
            guard context.exception == nil,
                  let render = core.invokeMethod("renderMoon", withArguments: [texture, geometry, 640]),
                  let pixels = render.objectForKeyedSubscript("pixels") else { throw MoonAtlasError.processing }
            let reference = try Self.referenceImage(pixels, size: 640, in: context)
            let features = try JSONDecoder().decode([MoonAtlasFeature].self, from: Data(contentsOf: root.appendingPathComponent("assets/features.json")))
            return MoonAtlasResult(fit: fit, surface: surface, reference: reference, features: features)
        }
    }

    private static func pixels(_ image: CGImage, in context: JSContext) throws -> JSValue {
        let count = image.width * image.height * 4
        guard let bytes = calloc(count, 1) else { throw MoonAtlasError.processing }
        guard let bitmap = CGContext(data: bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                     bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            free(bytes); throw MoonAtlasError.processing
        }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // The JS engine owns this allocation until its typed array is collected.
        guard let object = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef, kJSTypedArrayTypeUint8ClampedArray,
                                                                bytes, count, { pointer, _ in free(pointer) }, nil, nil),
              let value = JSValue(jsValueRef: object, in: context) else { throw MoonAtlasError.processing }
        return value
    }

    private static func referenceImage(_ pixels: JSValue, size: Int, in context: JSContext) throws -> UIImage {
        guard let object = JSValueToObject(context.jsGlobalContextRef, pixels.jsValueRef, nil),
              JSObjectGetTypedArrayByteLength(context.jsGlobalContextRef, object, nil) == size * size * 4,
              let bytes = JSObjectGetTypedArrayBytesPtr(context.jsGlobalContextRef, object, nil) else { throw MoonAtlasError.processing }
        let data = Data(bytes: bytes, count: size * size * 4)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                  decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw MoonAtlasError.processing }
        return UIImage(cgImage: image)
    }

    private static func captureDate(source: CGImageSource, fallback: Date?) -> Date? {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any],
           let value = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.isLenient = false
            if let zone = exif["OffsetTimeOriginal"] as? String {
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
                if let date = formatter.date(from: value + zone) { return date }
            } else if let date = formatter.date(from: value) { return date }
        }
        return fallback
    }
}
