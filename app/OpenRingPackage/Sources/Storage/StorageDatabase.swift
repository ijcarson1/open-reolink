import Foundation
import GRDB

/// Owns the SQLite database queue and applies the schema migration.
///
/// Path: `~/Library/Application Support/open-reolink/open-reolink.db` (per
/// ADR-0005). The old OpenRing DB under `open-ring/` is left untouched.
///
/// Construct with `inMemory()` for unit / integration tests; the migration
/// runs identically against an in-memory queue.
public final class StorageDatabase: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    private init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public static func openDefault() throws -> StorageDatabase {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("open-reolink", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("open-reolink.db").path
        let queue = try DatabaseQueue(path: path)
        let db = StorageDatabase(dbQueue: queue)
        try db.migrate()
        return db
    }

    public static func inMemory() throws -> StorageDatabase {
        let queue = try DatabaseQueue()
        let db = StorageDatabase(dbQueue: queue)
        try db.migrate()
        return db
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_reolink_initial") { db in
            try db.create(table: "cameras") { t in
                t.column("id", .text).primaryKey()
                t.column("display_name", .text).notNull()
                t.column("lan_ip", .text).notNull()
                t.column("cgi_scheme", .text).notNull().defaults(to: "https")
                t.column("cgi_port", .integer).notNull().defaults(to: 443)
                t.column("rtsp_port", .integer).notNull().defaults(to: 554)
                t.column("onvif_port", .integer).notNull().defaults(to: 8000)
                t.column("kind", .text).notNull()
                t.column("model", .text)
                t.column("firmware_version", .text)
                t.column("admin_username", .text).notNull().defaults(to: "admin")
                t.column("events_username", .text)
                t.column("capabilities_json", .text)
                t.column("discovered_via", .text).notNull().defaults(to: "manual")
                t.column("last_seen_at", .integer)
                t.column("is_online", .integer).notNull().defaults(to: 1)
                t.column("created_at", .integer).notNull().defaults(sql: "(strftime('%s', 'now'))")
                t.column("updated_at", .integer).notNull().defaults(sql: "(strftime('%s', 'now'))")
            }

            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("camera_id", .text).notNull().references("cameras", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("ai_class", .text)
                t.column("onvif_topic", .text)
                t.column("occurred_at", .integer).notNull()
                t.column("received_at", .integer).notNull().defaults(sql: "(strftime('%s', 'now'))")
                t.column("snapshot_path", .text)
                t.column("ai_summary", .text)
                t.column("important", .integer).notNull().defaults(to: 0)
                t.column("clip_url", .text)
            }
            try db.create(index: "idx_events_camera_occurred",
                          on: "events",
                          columns: ["camera_id", "occurred_at"])
            try db.create(index: "idx_events_kind", on: "events", columns: ["kind"])

            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }
}
