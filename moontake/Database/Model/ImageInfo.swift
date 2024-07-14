//
//  ImageInfo.swift
//  moontake
//
//  Created by zici on 12/7/24.
//

import Foundation
import GRDB
import UIKit
import ZCCalendar

struct ImageInfo: Identifiable, Hashable {
    var id: Int64?
    
    var creationTime: Int64?
    var modificationTime: Int64?
    
    var dataId: String
    var width: Int
    var height: Int
    var latitude: Double?
    var longitude: Double?
}

extension ImageInfo: Codable {
    enum Columns: String, ColumnExpression {
        case id
        
        static let creationTime = Column(CodingKeys.creationTime)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, creationTime = "creation_time", modificationTime = "modification_time", dataId = "data_id", width, height, latitude, longitude
    }
}

extension ImageInfo: TableRecord {
    static var databaseTableName: String = "image_info"
}

extension ImageInfo: FetchableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension ImageInfo: TimestampedRecord {
    
}

extension ImageInfo {
    var thumbnailURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("无法获取 Documents 目录")
            return nil
        }
        
        // 构建 imageData 子目录路径
        let imageDataDirectory = documentsDirectory.appendingPathComponent("imageData")
        
        // 构建文件路径
        let thumbnailURL = imageDataDirectory.appendingPathComponent("\(dataId)_thumbnail")
        
        return thumbnailURL
    }
    
    var creationDay: GregorianDay? {
        guard let creationTime = creationTime else { return nil }
        let day = GregorianDay(nanoSeconds: creationTime)
        
        return day
    }
}
