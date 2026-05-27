import Foundation
import GRDB
import ReolinkClient

public final class CameraRepository: Sendable {
    private let database: StorageDatabase

    public init(database: StorageDatabase) {
        self.database = database
    }

    public func list() throws -> [Camera] {
        try database.dbQueue.read { db in
            try Row
                .fetchAll(db, sql: "SELECT * FROM cameras ORDER BY created_at ASC")
                .map { try Self.decode(row: $0) }
        }
    }

    public func get(id: UUID) throws -> Camera? {
        try database.dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM cameras WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.decode(row: row)
        }
    }

    public func insert(_ camera: Camera) throws {
        try database.dbQueue.write { db in
            try Self.upsert(camera: camera, into: db)
        }
    }

    public func update(_ camera: Camera) throws {
        var updated = camera
        updated.updatedAt = Date()
        try database.dbQueue.write { db in
            try Self.upsert(camera: updated, into: db)
        }
    }

    public func delete(id: UUID) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM cameras WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Row <-> Camera

    private static func upsert(camera: Camera, into db: Database) throws {
        let capabilitiesJSON = try encodeCapabilities(camera.capabilities)
        try db.execute(sql: """
            INSERT OR REPLACE INTO cameras (
                id, display_name, lan_ip, cgi_scheme, cgi_port, rtsp_port, onvif_port,
                kind, model, firmware_version, admin_username, events_username,
                capabilities_json, discovered_via, last_seen_at, is_online,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            camera.id.uuidString,
            camera.displayName,
            camera.lanIP,
            camera.cgiScheme,
            camera.cgiPort,
            camera.rtspPort,
            camera.onvifPort,
            camera.kind.rawValue,
            camera.model,
            camera.firmwareVersion,
            camera.adminUsername,
            camera.eventsUsername,
            capabilitiesJSON,
            camera.discoveredVia.rawValue,
            camera.lastSeenAt.map { Int($0.timeIntervalSince1970) },
            camera.isOnline ? 1 : 0,
            Int(camera.createdAt.timeIntervalSince1970),
            Int(camera.updatedAt.timeIntervalSince1970),
        ])
    }

    static func decode(row: Row) throws -> Camera {
        guard let uuid = UUID(uuidString: row["id"]) else {
            throw CameraRepositoryError.malformedRow("invalid UUID: \(row["id"] ?? "<nil>")")
        }
        let kindString: String = row["kind"]
        guard let kind = CameraKind(rawValue: kindString) else {
            throw CameraRepositoryError.malformedRow("unknown kind: \(kindString)")
        }
        let sourceString: String = row["discovered_via"]
        guard let source = CameraDiscoverySource(rawValue: sourceString) else {
            throw CameraRepositoryError.malformedRow("unknown discovered_via: \(sourceString)")
        }
        let capabilitiesJSON: String? = row["capabilities_json"]
        let capabilities = try decodeCapabilities(capabilitiesJSON)
        return Camera(
            id: uuid,
            displayName: row["display_name"],
            lanIP: row["lan_ip"],
            kind: kind,
            cgiScheme: row["cgi_scheme"],
            cgiPort: row["cgi_port"],
            rtspPort: row["rtsp_port"],
            onvifPort: row["onvif_port"],
            model: row["model"],
            firmwareVersion: row["firmware_version"],
            adminUsername: row["admin_username"],
            eventsUsername: row["events_username"],
            capabilities: capabilities,
            discoveredVia: source,
            lastSeenAt: (row["last_seen_at"] as Int?).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            isOnline: (row["is_online"] as Int?) ?? 1 != 0,
            createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row["updated_at"] as Int))
        )
    }

    private static func encodeCapabilities(_ capabilities: CameraCapabilities?) throws -> String? {
        guard let capabilities else { return nil }
        let data = try JSONEncoder().encode(capabilities)
        return String(data: data, encoding: .utf8)
    }

    private static func decodeCapabilities(_ json: String?) throws -> CameraCapabilities? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(CameraCapabilities.self, from: data)
    }
}

public enum CameraRepositoryError: Error, Sendable, Equatable {
    case malformedRow(String)
}
