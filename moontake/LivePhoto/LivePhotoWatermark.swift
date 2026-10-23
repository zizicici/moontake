import AVFoundation
import CoreImage
import ImageIO
import UIKit

/// Edits both resources before Photos sees them. The still's Apple maker note,
/// movie content identifier, audio and still-image time are retained as a pair.
enum LivePhotoWatermark {
  enum Failure: LocalizedError {
    case invalidPair, image, video, cancelled
    var errorDescription: String? { String(localized: "live_photo.processing_failed") }
  }
  struct Still {
    let data: Data
    let footer: CGImage
    let originalSize: CGSize
    let size: CGSize
    let fileType: FileType
  }
  static func identifier(in data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
      let apple = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]
    else { return nil }
    return apple["17"] as? String
  }
  /// The existing watermark renderer is also used for the movie footer: text,
  /// date, phase and custom location are rasterized once, never once per frame.
  static func still(_ source: Data, date: Date, locationName: String?, fileType: FileType) throws
    -> Still
  {
    try autoreleasepool {
      guard let original = UIImage(data: source), let id = identifier(in: source),
        let marked = ImageSaver.addWaterMarkToBottomOfImage(
          image: original, date: date, customLocationName: locationName),
        let cg = marked.cgImage,
        let footer = cg.cropping(
          to: CGRect(
            x: 0, y: cg.height - Int(360 * marked.scale), width: cg.width,
            height: Int(360 * marked.scale))),
        let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
        var properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
      else { throw Failure.image }
      // The pixels are now upright. Retaining the old orientation would rotate twice.
      properties[kCGImagePropertyOrientation as String] = 1
      properties[kCGImagePropertyPixelWidth as String] = cg.width
      properties[kCGImagePropertyPixelHeight as String] = cg.height
      var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
      exif[kCGImagePropertyExifPixelXDimension as String] = cg.width
      exif[kCGImagePropertyExifPixelYDimension as String] = cg.height
      properties[kCGImagePropertyExifDictionary as String] = exif
      if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
        tiff[kCGImagePropertyTIFFOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary as String] = tiff
      }
      properties[kCGImageDestinationLossyCompressionQuality as String] = 0.95
      let encoded = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          encoded, fileType.system.rawValue as CFString, 1, nil)
      else { throw Failure.image }
      CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination), identifier(in: encoded as Data) == id else {
        throw Failure.invalidPair
      }
      return Still(
        data: encoded as Data, footer: footer, originalSize: original.size,
        size: CGSize(width: cg.width, height: cg.height), fileType: fileType)
    }
  }

  static func movie(
    _ source: URL, to destination: URL, still: Still, identifier: String,
    cancellation: LivePhotoCancellation = LivePhotoCancellation()
  ) async throws {
    try cancellation.check()
    let asset = AVURLAsset(url: source)
    let tracks = try await asset.load(.tracks)
    let metadata = try await asset.load(.metadata)
    guard let video = tracks.first(where: { $0.mediaType == .video }),
      let id = metadata.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier }),
      try await id.load(.stringValue) == identifier
    else { throw Failure.invalidPair }
    let duration = try await asset.load(.duration)
    guard duration.isNumeric, duration.seconds > 0, duration.seconds <= 15 else {
      throw Failure.video
    }
    let descriptions = try await video.load(.formatDescriptions)
    guard let description = descriptions.first else { throw Failure.video }
    let encoded = CMVideoFormatDescriptionGetDimensions(description)
    let natural = CGSize(width: Int(encoded.width), height: Int(encoded.height))
    let transform = try await video.load(.preferredTransform)
    let bounds = CGRect(origin: .zero, size: natural).applying(transform).standardized
    guard bounds.width > 0, bounds.height > 0, bounds.width <= 4096, bounds.height <= 4096,
      still.originalSize.width > 0, still.originalSize.height > 0
    else { throw Failure.video }
    // Native Live movies carry a smaller clean aperture for playback zoom.
    // Use the encoded raster, which matches the full-resolution still's field
    // of view. Baking the clean aperture would enlarge/crop the scene once,
    // and copying the original Live transforms would crop the new footer again.
    let videoWidth = Int(bounds.width.rounded()) / 2 * 2
    let videoHeight = Int(bounds.height.rounded()) / 2 * 2
    let footerHeight = max(
      2,
      Int(
        (Double(videoWidth) * Double(still.footer.height) / Double(still.footer.width) / 2)
          .rounded()) * 2)
    // A small difference can arise from encoder alignment, not a different framing.
    guard
      abs(
        Double(videoWidth) / Double(videoHeight)
          - Double(still.originalSize.width / still.originalSize.height))
        < 0.03
    else { throw Failure.video }
    let outputHeight = videoHeight + footerHeight
    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
    writer.metadata = metadata.filter {
      [
        .quickTimeMetadataContentIdentifier, .quickTimeMetadataCreationDate,
        .quickTimeMetadataLocationISO6709, .quickTimeMetadataMake, .quickTimeMetadataModel,
        .quickTimeMetadataSoftware,
      ].contains($0.identifier)
    }
    // Decode in order; a video composition can queue many full-size frames.
    let videoOutput = AVAssetReaderTrackOutput(
      track: video,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    videoOutput.alwaysCopiesSampleData = false
    // Track transforms use top-left coordinates, Core Image uses bottom-left.
    let upright = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: natural.height)
      .concatenating(transform)
      .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
      .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height))
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: videoWidth,
      AVVideoHeightKey: outputHeight,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: max(2_000_000, videoWidth * outputHeight * 5),
        AVVideoAllowFrameReorderingKey: false,
      ],
    ]
    guard reader.canAdd(videoOutput),
      writer.canApply(outputSettings: settings, forMediaType: .video)
    else {
      throw Failure.video
    }
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    videoInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(videoInput) else { throw Failure.video }
    reader.add(videoOutput)
    writer.add(videoInput)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: videoWidth,
        kCVPixelBufferHeightKey as String: outputHeight,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ])
    var passthrough: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
    for track in tracks where track.mediaType == .audio {
      let descriptions = try await track.load(.formatDescriptions)
      guard let format = descriptions.first else { throw Failure.invalidPair }
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      let input = AVAssetWriterInput(
        mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: format)
      input.expectsMediaDataInRealTime = false
      input.metadata = try await track.load(.metadata)
      guard reader.canAdd(output), writer.canAdd(input) else { throw Failure.invalidPair }
      reader.add(output)
      writer.add(input)
      passthrough.append((output, input))
    }
    let marker = try await stillImageTime(in: asset, tracks: tracks, duration: duration)
    var markerFormat: CMMetadataFormatDescription?
    let specification: [String: Any] = [
      kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
        stillImageTimeIdentifier,
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
        kCMMetadataBaseDataType_SInt8
        as String,
    ]
    guard
      CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
        allocator: kCFAllocatorDefault,
        metadataType: kCMMetadataFormatType_Boxed,
        metadataSpecifications: [specification] as CFArray,
        formatDescriptionOut: &markerFormat) == noErr
    else { throw Failure.invalidPair }
    let markerInput = AVAssetWriterInput(
      mediaType: .metadata, outputSettings: nil, sourceFormatHint: markerFormat)
    guard writer.canAdd(markerInput) else { throw Failure.invalidPair }
    writer.add(markerInput)
    let markerAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: markerInput)
    // The decoder, encoder and one reusable footer own bounded frame buffers.
    let footer = CIImage(cgImage: still.footer).transformed(
      by: CGAffineTransform(
        scaleX: CGFloat(videoWidth) / CGFloat(still.footer.width),
        y: CGFloat(footerHeight) / CGFloat(still.footer.height)))
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    defer { context.clearCaches() }
    try cancellation.check()
    guard writer.startWriting(), reader.startReading() else {
      throw writer.error ?? reader.error ?? Failure.video
    }
    writer.startSession(atSourceTime: .zero)
    guard markerAdaptor.append(marker) else {
      reader.cancelReading()
      writer.cancelWriting()
      throw writer.error ?? Failure.invalidPair
    }
    markerInput.markAsFinished()
    defer { cancellation.onCancel(nil) }
    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        // All track callbacks use one serial queue. At most one source and
        // destination video frame are held by our code at a time.
        let queue = DispatchQueue(label: "livePhoto.watermark", qos: .userInitiated)
        var remaining = passthrough.count + 1
        var completed = false
        var timer: DispatchSourceTimer? = DispatchSource.makeTimerSource(queue: queue)
        func fail(_ error: Error) {
          guard !completed else { return }
          completed = true
          timer?.cancel()
          timer = nil
          reader.cancelReading()
          writer.cancelWriting()
          continuation.resume(throwing: error)
        }
        func finishTrack() {
          remaining -= 1
          guard remaining == 0, !completed else { return }
          if reader.status == .failed {
            fail(reader.error ?? Failure.video)
            return
          }
          writer.endSession(atSourceTime: duration)
          writer.finishWriting {
            queue.async {
              guard !completed else { return }
              if writer.status == .completed {
                completed = true
                timer?.cancel()
                timer = nil
                continuation.resume()
              } else {
                fail(writer.error ?? Failure.video)
              }
            }
          }
        }
        // Avoid retaining a stuck encoder forever after resource exhaustion.
        timer?.schedule(deadline: .now() + 60)
        timer?.setEventHandler { fail(Failure.video) }
        timer?.resume()
        cancellation.onCancel { queue.async { fail(CancellationError()) } }
        var pendingSample: CMSampleBuffer?
        var waitingForBuffer = false
        var videoFinished = false
        let allocationLimit =
          [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary
        func pumpVideo() {
          guard !completed, !videoFinished, !waitingForBuffer else { return }
          while videoInput.isReadyForMoreMediaData {
            do {
              try cancellation.check()
              let status = try autoreleasepool { () throws -> Int in
                if pendingSample == nil { pendingSample = videoOutput.copyNextSampleBuffer() }
                guard let sample = pendingSample else { return 0 }
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                  let pool = adaptor.pixelBufferPool
                else { throw Failure.video }
                var pixel: CVPixelBuffer?
                let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                  kCFAllocatorDefault, pool, allocationLimit, &pixel)
                if allocation == kCVReturnWouldExceedAllocationThreshold { return 2 }
                guard allocation == kCVReturnSuccess, let pixel else { throw Failure.video }
                let content = CIImage(cvPixelBuffer: sourceBuffer).transformed(by: upright)
                  .cropped(to: CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight))
                  .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(footerHeight)))
                let frame = content.composited(over: footer)
                context.render(
                  frame, to: pixel,
                  bounds: CGRect(x: 0, y: 0, width: videoWidth, height: outputHeight),
                  colorSpace: colorSpace)
                guard
                  adaptor.append(
                    pixel, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
                else { throw writer.error ?? Failure.video }
                pendingSample = nil
                return 1
              }
              if status == 0 {
                videoFinished = true
                videoInput.markAsFinished()
                finishTrack()
                return
              }
              if status == 2 {
                // Retain just this source frame until an encoder buffer is
                // released. Do not drop frames or allocate without a bound.
                waitingForBuffer = true
                queue.asyncAfter(deadline: .now() + 0.002) {
                  waitingForBuffer = false
                  pumpVideo()
                }
                return
              }
            } catch {
              fail(error)
              return
            }
          }
        }
        videoInput.requestMediaDataWhenReady(on: queue) { pumpVideo() }
        for (output, input) in passthrough {
          input.requestMediaDataWhenReady(on: queue) {
            guard !completed else { return }
            while input.isReadyForMoreMediaData {
              do { try cancellation.check() } catch {
                fail(error)
                return
              }
              guard let sample = output.copyNextSampleBuffer() else {
                input.markAsFinished()
                finishTrack()
                return
              }
              guard input.append(sample) else {
                fail(writer.error ?? Failure.video)
                return
              }
            }
          }
        }
      }
    } catch {
      reader.cancelReading()
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  static let stillImageTimeIdentifier = "mdta/com.apple.quicktime.still-image-time"

  /// Capture orientation, clean-aperture/stabilization and still-image transform
  /// metadata refer to the old canvas. Rebuild just the still marker, preserving
  /// its value and timestamp; never apply old geometry to an upright framed pair.
  private static func stillImageTime(in asset: AVAsset, tracks: [AVAssetTrack], duration: CMTime)
    async throws
    -> AVTimedMetadataGroup
  {
    for track in tracks where track.mediaType == .metadata {
      let formats = try await track.load(.formatDescriptions)
      guard
        formats.contains(where: {
          (CMMetadataFormatDescriptionGetIdentifiers($0) as? [String])?.contains(
            stillImageTimeIdentifier)
            == true
        })
      else { continue }
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      guard reader.canAdd(output) else { throw Failure.invalidPair }
      reader.add(output)
      let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
      guard reader.startReading() else { throw reader.error ?? Failure.invalidPair }
      defer { reader.cancelReading() }
      while let group = adaptor.nextTimedMetadataGroup() {
        guard
          let source = group.items.first(where: {
            $0.identifier?.rawValue == stillImageTimeIdentifier
          })
        else { continue }
        guard group.timeRange.start.isNumeric, group.timeRange.start >= .zero,
          group.timeRange.start < duration, let value = try await source.load(.numberValue)
        else { throw Failure.invalidPair }
        let marker = AVMutableMetadataItem()
        marker.identifier = AVMetadataIdentifier(rawValue: stillImageTimeIdentifier)
        marker.dataType = kCMMetadataBaseDataType_SInt8 as String
        marker.value = value
        return AVTimedMetadataGroup(items: [marker], timeRange: group.timeRange)
      }
    }
    throw Failure.invalidPair
  }

}
