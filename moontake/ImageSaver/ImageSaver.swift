//
//  PhotoCaptureProcessor+WaterMark.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/8.
//

import Foundation
import UIKit
import Photos

struct ImageSaver {
    enum TargetType {
        case origin
        case watermark
    }
    
    static func saveImage(_ photoData: Data, targets: [TargetType], fileType: FileType, location: CLLocation?, width: Int, height: Int, date: Date, toDatabase: Bool, completion: (() -> ())?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = fileType.system.rawValue
                    
                    if targets.contains(.origin) {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.location = location
                        creationRequest.addResource(with: .photo, data: photoData, options: options)
                    }
                    if targets.contains(.watermark), let newData = self.addWaterMark(for: photoData, date: date) {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.location = location
                        creationRequest.addResource(with: .photo, data: newData, options: options)
                    }
                    if toDatabase {
                        AlbumManager.shared.addImage(data: photoData, fileType: fileType, width: width, height: height, latitude: location?.coordinate.latitude, longitude: location?.coordinate.latitude)
                    }
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving photo to photo library: \(error)")
                    }
                    completion?()
                })
            } else {
                completion?()
            }
        }
    }
}

extension ImageSaver {
    static func addWaterMark(for photoData: Data, date: Date) -> Data? {
        var newData: Data?
        if let image = UIImage(data: photoData), let newImage = addWaterMarkToBottomOfImage(image: image, date: date) {
            let exifData = getExifData(from: photoData)
            
            if #available(iOS 17.0, *) {
                if let data = newImage.heicData() {
                    newData = data
                }
                if let data = newData, let exifData = exifData {
                    newData = addExifData(to: data, exifData: exifData)
                }
            } else {
                if let data = newImage.jpegData(compressionQuality: 0.8) {
                    newData = data
                }
                if let data = newData, let exifData = exifData {
                    newData = addExifData(to: data, exifData: exifData)
                }
            }
        }
        return newData
    }
    
    static func getExifData(from imageData: Data) -> [AnyHashable : Any]? {
        let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)
        let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource!, 0, nil) as! [AnyHashable : Any]
        return imageProperties[kCGImagePropertyExifDictionary as String] as? [AnyHashable : Any]
    }

    static func addExifData(to imageData: Data, exifData: [AnyHashable : Any]) -> Data? {
        let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil)!
        var imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as! [AnyHashable : Any]
        var metadata = (imageProperties[(kCGImagePropertyExifDictionary as String)] as? [AnyHashable : Any]) ?? [:]
        
        for (key, value) in exifData {
            if metadata[key] == nil {
                metadata[key] = value
            }
        }
        imageProperties[(kCGImagePropertyExifDictionary as String)] = metadata
        
        let destinationData = NSMutableData()
        let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, CGImageSourceGetType(imageSource)!, 1, nil)
        CGImageDestinationAddImageFromSource(destination!, imageSource, 0, (imageProperties as CFDictionary?))
        CGImageDestinationFinalize(destination!)
        
        return destinationData as Data
    }
    
    static func addWaterMarkToBottomOfImage(image: UIImage, date: Date) -> UIImage? {
        let imageSize = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: imageSize.width, height: imageSize.height + 360), false, scale)
        
        // Photo
        image.draw(at: .zero)
        
        // WaterMark Background
        let whiteRect = CGRect(x: 0, y: imageSize.height, width: imageSize.width, height: 360)
        UIColor.white.setFill()
        UIRectFill(whiteRect)
        
        // First Line
        let firstAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 80, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        let phasePercent = MoonManager.shared.getPhasePercent(date)
        let firstText: String = String(format: "%@ %.1f%%", MoonManager.shared.getPhaseName(date), phasePercent * 100)
        let firstAttributedString = NSAttributedString(string: firstText, attributes: firstAttributes)
        
        let firstHeight = firstAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude).height
        let firstTextRect = CGRect(x: 80.0, y: imageSize.height + 70.0, width: imageSize.width - 80.0, height: firstHeight)

        firstAttributedString.draw(in: firstTextRect)
        
        // Second Line
        let secondAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .light),
            .foregroundColor: UIColor.black.withAlphaComponent(0.6)
        ]
        let secondText: String = date.formatted(date: .numeric, time: .standard)
        let secondAttributedString = NSAttributedString(string: secondText, attributes: secondAttributes)
        
        let secondHeight = secondAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude).height
        let secondTextRect = CGRect(x: 80.0, y: firstTextRect.maxY + 48.0, width: imageSize.width - 80.0, height: secondHeight)
        
        secondAttributedString.draw(in: secondTextRect)
        // Promotion
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.right
        paragraphStyle.lineSpacing = 30.0
        let promotionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 60, weight: .light),
            .foregroundColor: UIColor.black.withAlphaComponent(0.6),
            .paragraphStyle: paragraphStyle
        ]
        let promotionText: String = String(localized: "moontake\nA Moon Camera")
        let promotionAttributedString = NSMutableAttributedString(string: promotionText, attributes: promotionAttributes)
        let range = (promotionText as NSString).range(of: "moontake")
        promotionAttributedString.addAttributes([.font: UIFont.systemFont(ofSize: 72, weight: .medium), .foregroundColor: UIColor.black], range: range)
        
        let promotionSize = promotionAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude)
        let promotionTextRect = CGRect(x: imageSize.width - 340.0 - promotionSize.width, y: imageSize.height + (360 - promotionSize.height) / 2.0, width: promotionSize.width, height: promotionSize.height)
        
        promotionAttributedString.draw(in: promotionTextRect)
        
        // Icon
        if let logoImage = UIImage(named: "AppIcon") {
            // 创建圆角路径
            let cornerRadius: CGFloat = 50.0
            let path = UIBezierPath(roundedRect: CGRect(x: imageSize.width - 280, y: imageSize.height + 80, width: 200, height: 200), cornerRadius: cornerRadius)
            path.addClip()
            
            logoImage.draw(in: CGRect(x: imageSize.width - 280, y: imageSize.height + 80, width: 200, height: 200))
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
