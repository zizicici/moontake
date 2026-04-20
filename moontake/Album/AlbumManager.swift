//
//  AlbumManager.swift
//  moontake
//
//  Created by zici on 11/7/24.
//

import Foundation
import GRDB
import UIKit

class AlbumManager: NSObject {
    static let shared = AlbumManager()
    
    func addImage(data: Data, fileType: FileType, width: Int, height: Int, latitude: Double?, longitude: Double?) {
        let dataId = UUID().uuidString
        if saveDataToDocumentsDirectory(data: data, fileName: dataId) {
            let result = AppDatabase.shared.add(imageInfo: ImageInfo(dataId: dataId, fileType: fileType, width: width, height: height, latitude: latitude, longitude: longitude))
            print(result)
        }
    }

    func clearImages() -> Bool {
        let result = AppDatabase.shared.deleteAllImages()
        guard result else {
            return false
        }

        deleteImageDataDirectory()
        return true
    }
    
    func fetchAllImages(completion: (([ImageInfo]) -> ())? ) {
        AppDatabase.shared.reader?.asyncRead{ dbResult in
            do {
                let db = try dbResult.get()
                let creationTimeColumn = ImageInfo.Columns.creationTime
                let imageInfos = try ImageInfo.order(creationTimeColumn.desc).fetchAll(db)
                DispatchQueue.main.async {
                    completion?(imageInfos)
                }
            }
            catch {
                print(error)
                DispatchQueue.main.async {
                    completion?([])
                }
            }
        }
    }
    
    func downsampleImage(for data: Data, maxSize: Float) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions), let downsampledImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) {
            return UIImage(cgImage: downsampledImage)
        } else {
            return nil
        }
    }
    
    func saveDataToDocumentsDirectory(data: Data, fileName: String) -> Bool {
        guard let imageDataDirectory = imageDataDirectory(createIfNeeded: true) else {
            return false
        }
        
        guard let thumbnail = downsampleImage(for: data, maxSize: 560), let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            return false
        }
        
        // 创建文件路径
        let fileURL = imageDataDirectory.appendingPathComponent(fileName)
        let thumbnailURL = imageDataDirectory.appendingPathComponent("\(fileName)_thumbnail")

        do {
            // 将 Data 对象写入文件
            try thumbnailData.write(to: thumbnailURL)
            try data.write(to: fileURL)
            print("File saved successfully to \(fileURL.path)")
            return true
        } catch {
            print("Failed to save file: \(error.localizedDescription)")
            return false
        }
    }

    private func imageDataDirectory(createIfNeeded: Bool) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to locate Documents directory.")
            return nil
        }

        let imageDataDirectory = documentsDirectory.appendingPathComponent("imageData")
        guard createIfNeeded, !FileManager.default.fileExists(atPath: imageDataDirectory.path) else {
            return imageDataDirectory
        }

        do {
            try FileManager.default.createDirectory(at: imageDataDirectory, withIntermediateDirectories: true, attributes: nil)
            print("Created imageData directory at \(imageDataDirectory.path)")
            return imageDataDirectory
        } catch {
            print("Failed to create imageData directory: \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteImageDataDirectory() {
        guard let imageDataDirectory = imageDataDirectory(createIfNeeded: false),
              FileManager.default.fileExists(atPath: imageDataDirectory.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: imageDataDirectory)
            print("Deleted imageData directory at \(imageDataDirectory.path)")
        } catch {
            print("Failed to delete imageData directory: \(error.localizedDescription)")
        }
    }
}
