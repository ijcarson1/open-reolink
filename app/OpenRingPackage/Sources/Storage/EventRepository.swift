import Foundation
import GRDB
import ReolinkClient

/// Minimal `EventRepository` for Slice 2.
///
/// The table is created and the type modelled, but writes are not exercised
/// until Slice 5 (`EventCoordinator` wires real ONVIF events). The CRUD here
/// exists so the table contract is testable and so Slice 5 can drop in without
/// re-shaping anything.
public final class EventRepository: Sendable {
    private let database: StorageDatabase

    public init(database: StorageDatabase) {
        self.database = database
    }

    public func insert(_ event: StoredEvent) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO events (
                    id, camera_id, kind, ai_class, onvif_topic, occurred_at,
                    received_at, snapshot_path, ai_summary, important, clip_url
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                event.id.uuidString,
                event.cameraId.uuidString,
                event.kind.rawValue,
                event.aiClass,
                event.onvifTopic,
                Int(event.occurredAt.timeIntervalSince1970),
                Int(event.receivedAt.timeIntervalSince1970),
                event.snapshotPath,
                event.aiSummary,
                event.important ? 1 : 0,
                event.clipURL,
            ])
        }
    }

    public func recent(for cameraId: UUID, limit: Int = 50) throws -> [StoredEvent] {
        try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM events
                WHERE camera_id = ?
                ORDER BY occurred_at DESC
                LIMIT ?
            """, arguments: [cameraId.uuidString, limit]).map(Self.decode)
        }
    }

    public func deleteOlderThan(_ cutoff: Date) throws -> Int {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events WHERE received_at < ?",
                           arguments: [Int(cutoff.timeIntervalSince1970)])
            return db.changesCount
        }
    }

    public func deleteAll() throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events")
        }
    }

    private static func decode(row: Row) -> StoredEvent {
        StoredEvent(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            cameraId: UUID(uuidString: row["camera_id"]) ?? UUID(),
            kind: StoredEvent.Kind(rawValue: row["kind"]) ?? .motion,
            aiClass: row["ai_class"],
            onvifTopic: row["onvif_topic"],
            occurredAt: Date(timeIntervalSince1970: TimeInterval(row["occurred_at"] as Int)),
            receivedAt: Date(timeIntervalSince1970: TimeInterval(row["received_at"] as Int)),
            snapshotPath: row["snapshot_path"],
            aiSummary: row["ai_summary"],
            important: (row["important"] as Int?) ?? 0 != 0,
            clipURL: row["clip_url"]
        )
    }
}

public struct StoredEvent: Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case motion
        case ring
    }

    public let id: UUID
    public let cameraId: UUID
    public let kind: Kind
    public let aiClass: String?
    public let onvifTopic: String?
    public let occurredAt: Date
    public let receivedAt: Date
    public let snapshotPath: String?
    public let aiSummary: String?
    public let important: Bool
    public let clipURL: String?

    public init(
        id: UUID = UUID(),
        cameraId: UUID,
        kind: Kind,
        aiClass: String? = nil,
        onvifTopic: String? = nil,
        occurredAt: Date,
        receivedAt: Date = Date(),
        snapshotPath: String? = nil,
        aiSummary: String? = nil,
        important: Bool = false,
        clipURL: String? = nil
    ) {
        self.id = id
        self.cameraId = cameraId
        self.kind = kind
        self.aiClass = aiClass
        self.onvifTopic = onvifTopic
        self.occurredAt = occurredAt
        self.receivedAt = receivedAt
        self.snapshotPath = snapshotPath
        self.aiSummary = aiSummary
        self.important = important
        self.clipURL = clipURL
    }
}
