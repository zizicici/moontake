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
        // 获取应用沙盒的 Documents 目录路径
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to locate Documents directory.")
            return false
        }
        
        // 创建 imageData 文件夹路径
        let imageDataDirectory = documentsDirectory.appendingPathComponent("imageData")
        
        // 检查 imageData 文件夹是否存在，如果不存在则创建它
        if !FileManager.default.fileExists(atPath: imageDataDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: imageDataDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Created imageData directory at \(imageDataDirectory.path)")
            } catch {
                print("Failed to create imageData directory: \(error.localizedDescription)")
                return false
            }
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
}
