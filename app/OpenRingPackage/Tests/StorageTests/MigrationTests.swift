import Foundation
import Testing
import GRDB
@testable import Storage

@Suite("v1_reolink_initial migration")
struct MigrationTests {

    @Test("Creates cameras, events, settings tables with the columns specified in ADR-0005")
    func columns() throws {
        let db = try StorageDatabase.inMemory()
        let cameras = try db.dbQueue.read { try $0.columns(in: "cameras") }
        let events = try db.dbQueue.read { try $0.columns(in: "events") }
        let settings = try db.dbQueue.read { try $0.columns(in: "settings") }

        let cameraColumns = Set(cameras.map(\.name))
        #expect(cameraColumns == [
            "id", "display_name", "lan_ip", "cgi_scheme", "cgi_port", "rtsp_port",
            "onvif_port", "kind", "model", "firmware_version", "admin_username",
            "events_username", "capabilities_json", "discovered_via", "last_seen_at",
            "is_online", "created_at", "updated_at",
        ])

        let eventColumns = Set(events.map(\.name))
        #expect(eventColumns == [
            "id", "camera_id", "kind", "ai_class", "onvif_topic", "occurred_at",
            "received_at", "snapshot_path", "ai_summary", "important", "clip_url",
        ])

        let settingsColumns = Set(settings.map(\.name))
        #expect(settingsColumns == ["key", "value"])
    }

    @Test("Required defaults match the schema (cgi_scheme=https, ports, discovered_via=manual, is_online=1)")
    func defaults() throws {
        let db = try StorageDatabase.inMemory()
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO cameras (id, display_name, lan_ip, kind)
                VALUES ('11111111-1111-1111-1111-111111111111', 'Cam', '192.0.2.10', 'camera')
            """)
        }
        let row = try db.dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM cameras")
        }
        let unwrapped = try #require(row)
        #expect(unwrapped["cgi_scheme"] == "https")
        #expect(unwrapped["cgi_port"] == 443)
        #expect(unwrapped["rtsp_port"] == 554)
        #expect(unwrapped["onvif_port"] == 8000)
        #expect(unwrapped["admin_username"] == "admin")
        #expect(unwrapped["discovered_via"] == "manual")
        #expect(unwrapped["is_online"] == 1)
        #expect((unwrapped["created_at"] as Int) > 0)
        #expect((unwrapped["updated_at"] as Int) > 0)
    }

    @Test("Indexes (camera_id, occurred_at) and (kind) on events exist")
    func indexes() throws {
        let db = try StorageDatabase.inMemory()
        let indexes = try db.dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list('events')")
        }
        let names = Set(indexes.compactMap { $0["name"] as String? })
        #expect(names.contains("idx_events_camera_occurred"))
        #expect(names.contains("idx_events_kind"))
    }

    @Test("ON DELETE CASCADE: deleting a camera removes its events")
    func cascade() throws {
        let db = try StorageDatabase.inMemory()
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO cameras (id, display_name, lan_ip, kind)
                VALUES ('cam-1', 'Cam', '192.0.2.10', 'camera')
            """)
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: """
                INSERT INTO events (id, camera_id, kind, occurred_at)
                VALUES ('evt-1', 'cam-1', 'motion', 1700000000)
            """)
            try db.execute(sql: "DELETE FROM cameras WHERE id = 'cam-1'")
        }
        let remaining = try db.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
        }
        #expect(remaining == 0)
    }
}
