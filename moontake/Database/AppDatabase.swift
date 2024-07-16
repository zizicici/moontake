//
//  AppDatabase.swift
//  moontake
//
//  Created by zici on 12/7/24.
//

import Foundation
import GRDB

extension Notification.Name {
    static let DatabaseUpdated = Notification.Name(rawValue: "com.zizicici.common.database.updated")
}

final class AppDatabase {
    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }
    
    private var dbWriter: (any DatabaseWriter)?

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
#if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
#endif
        migrator.registerMigration("create_image_info") { db in
            try db.create(table: "image_info") { table in
                table.autoIncrementedPrimaryKey("id")
                
                table.column("creation_time", .integer).notNull()
                table.column("modification_time", .integer).notNull()
                
                table.column("data_id", .text).notNull()
                table.column("file_type", .integer).notNull()
                table.column("width", .integer).notNull()
                table.column("height", .integer).notNull()
                table.column("latitude", .double)
                table.column("longitude", .double)
            }
        }
        
        return migrator
    }
    
    public func disconnect() {
        self.dbWriter = nil
    }
    
    public func reconnect() {
        do {
            let databasePool = try AppDatabase.generateDatabasePool()
            try migrator.migrate(databasePool)
            self.dbWriter = databasePool
        } catch {
            print(error)
        }
    }
}

extension AppDatabase {
    func add(imageInfo: ImageInfo) -> Bool {
        guard imageInfo.id == nil else {
            return false
        }
        do {
            try dbWriter?.write{ db in
                var saveImageInfo = imageInfo
                try saveImageInfo.save(db)
            }
        }
        catch {
            print(error)
            return false
        }
        NotificationCenter.default.post(name: NSNotification.Name.DatabaseUpdated, object: nil)
        return true
    }
    
    func update(imageInfo: ImageInfo) -> Bool {
        guard imageInfo.id != nil else {
            return false
        }
        do {
            _ = try dbWriter?.write{ db in
                var saveImageInfo = imageInfo
                try saveImageInfo.updateWithTimestamp(db)
            }
        }
        catch {
            print(error)
            return false
        }
        NotificationCenter.default.post(name: NSNotification.Name.DatabaseUpdated, object: nil)
        return true
    }
    
    func delete(imageInfo: ImageInfo) -> Bool {
        guard let imageInfoId = imageInfo.id else {
            return false
        }
        do {
            _ = try dbWriter?.write{ db in
                try ImageInfo.deleteAll(db, ids: [imageInfoId])
            }
        }
        catch {
            print(error)
            return false
        }
        NotificationCenter.default.post(name: NSNotification.Name.DatabaseUpdated, object: nil)
        return true
    }
}

extension AppDatabase {
    /// Provides a read-only access to the database
    var reader: DatabaseReader? {
        dbWriter
    }
}
