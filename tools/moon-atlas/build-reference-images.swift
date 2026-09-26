// swiftc -O build-reference-images.swift -o /tmp/moon-references
// /tmp/moon-references <source-directory> <catalog.json> <plan.json> <output-directory>
// Offline resampling of public-domain spacecraft data. No generated terrain,
// sharpening, invented detail, or runtime high-resolution texture is involved.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let radius = 1737.4 // km, IAU mean lunar radius used by the source products
let radians = Double.pi / 180

struct Feature: Decodable {
    let id: String
    let latitude, longitude, diameterKm: Double
    let type: String
}
struct Plan: Decodable {
    struct Source: Decodable {
        let file, projection: String
        let scaleMeters, centerX, centerY: Double?
        let insetPixels: Double?
        let cropPixels: [Double]?
    }
    struct Selection: Decodable {
        let source: String
        let heightKm: Double?
    }
    let sources: [String: Source]
    let features: [String: Selection]
}

struct Raster {
    let width, height: Int
    let pixels: [UInt8]
    init(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "Reference raster", code: 1, userInfo: [NSLocalizedDescriptionKey: url.path])
        }
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let decoded = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { throw NSError(domain: "Reference decode", code: 2) }
        pixels = data
    }
    func sample(_ x: Double, _ y: Double, wraps: Bool = false) -> [UInt8] {
        precondition(x.isFinite && y.isFinite)
        if !wraps { precondition(x >= 0 && x <= Double(width - 1) && y >= 0 && y <= Double(height - 1), "Crop leaves source coverage") }
        let x0 = Int(floor(x)), y0 = min(height - 1, max(0, Int(floor(y))))
        let y1 = min(height - 1, y0 + 1)
        let a = (x0 % width + width) % width, b = wraps ? (a + 1) % width : min(width - 1, a + 1)
        let dx = x - floor(x), dy = min(1, max(0, y - Double(y0)))
        return (0..<3).map { c in
            let top = Double(pixels[(y0 * width + a) * 4 + c]) * (1 - dx) + Double(pixels[(y0 * width + b) * 4 + c]) * dx
            let bottom = Double(pixels[(y1 * width + a) * 4 + c]) * (1 - dx) + Double(pixels[(y1 * width + b) * 4 + c]) * dx
            return UInt8((top * (1 - dy) + bottom * dy).rounded())
        }
    }
}

// Inverse azimuthal equidistant projection. The feature's geographic center
// is the center of the image; local north is up, east right. This avoids
// stretching high-latitude features by cropping the cylindrical source directly.
func coordinate(east: Double, north: Double, latitude: Double, longitude: Double) -> (Double, Double) {
    let distance = hypot(east, north)
    guard distance > 1e-12 else { return (latitude, longitude) }
    let angle = distance / radius
    let lat = asin(cos(angle) * sin(latitude) + north / distance * sin(angle) * cos(latitude))
    let lon = longitude + atan2(east * sin(angle), distance * cos(latitude) * cos(angle) - north * sin(latitude) * sin(angle))
    return (lat, lon)
}

func verifyProjection() {
    let center = coordinate(east: 0, north: 0, latitude: 0.8, longitude: -0.3)
    precondition(center.0 == 0.8 && center.1 == -0.3)
    let north = coordinate(east: 0, north: 50, latitude: 0.8, longitude: -0.3)
    precondition(abs(north.0 - (0.8 + 50 / radius)) < 1e-12 && abs(north.1 + 0.3) < 1e-12)
    let east = coordinate(east: 50, north: 0, latitude: 0, longitude: 0)
    precondition(abs(east.1 - 50 / radius) < 1e-12 && abs(east.0) < 1e-12)
}

verifyProjection()
precondition(CommandLine.arguments.count == 5, "Expected source-directory, catalog, plan, output-directory")
let arguments = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
let catalog = try JSONDecoder().decode([Feature].self, from: Data(contentsOf: arguments[1]))
let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: arguments[2]))
try FileManager.default.createDirectory(at: arguments[3], withIntermediateDirectories: true)
var rasters: [String: Raster] = [:]
for (id, source) in plan.sources { rasters[id] = try Raster(arguments[0].appendingPathComponent(source.file)) }

for feature in catalog {
    let selection = plan.features[feature.id]!
    let source = plan.sources[selection.source]!
    let raster = rasters[selection.source]!
    // NAC products already are north-up map projections. Recorded crops exclude
    // empty mosaic margins while retaining the complete crater outline.
    let native = source.projection == "native"
    let width = native ? 640 : 768
    let inset = source.insetPixels ?? 0
    let crop = source.cropPixels ?? [inset, inset, Double(raster.width) - 2 * inset, Double(raster.height) - 2 * inset]
    precondition(crop.count == 4 && crop[0] >= 0 && crop[1] >= 0 && crop[2] > 0 && crop[3] > 0)
    precondition(crop[0] + crop[2] <= Double(raster.width) && crop[1] + crop[3] <= Double(raster.height))
    let sourceWidth = crop[2], sourceHeight = crop[3]
    let height = native ? Int((640 * sourceHeight / sourceWidth).rounded()) : 512
    let heightKm = selection.heightKm ?? min(3000, max(320, feature.diameterKm * 1.5))
    var output = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let position: (Double, Double)
            if native {
                position = (crop[0] + (Double(x) + 0.5) * sourceWidth / Double(width) - 0.5,
                            crop[1] + (Double(y) + 0.5) * sourceHeight / Double(height) - 0.5)
            } else {
                let (latitude, longitude) = coordinate(
                    east: (Double(x) + 0.5 - Double(width) / 2) * heightKm / Double(height),
                    north: (Double(height) / 2 - Double(y) - 0.5) * heightKm / Double(height),
                    latitude: feature.latitude * radians, longitude: feature.longitude * radians)
                if source.projection == "equirectangular" {
                    position = ((longitude / (2 * .pi) + 0.5) * Double(raster.width) - 0.5,
                                (0.5 - latitude / .pi) * Double(raster.height) - 0.5)
                } else {
                    precondition(source.projection == "orthographic" && cos(latitude) * cos(longitude) > 0)
                    let pixelRadius = radius * 1000 / source.scaleMeters!
                    position = (source.centerX! + pixelRadius * cos(latitude) * sin(longitude),
                                source.centerY! - pixelRadius * sin(latitude))
                }
            }
            let color = raster.sample(position.0, position.1, wraps: source.projection == "equirectangular")
            for c in 0..<3 { output[(y * width + x) * 4 + c] = color[c] }
        }
    }
    let data = Data(output) as CFData
    let provider = CGDataProvider(data: data)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let url = arguments[3].appendingPathComponent("\(feature.id).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.60] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    print("\(feature.id): \(width)×\(height), \(try Data(contentsOf: url).count) bytes, \(selection.source)")
}
