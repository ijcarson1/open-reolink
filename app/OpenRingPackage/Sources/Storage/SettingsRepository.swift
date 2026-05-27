import Foundation
import GRDB

public final class SettingsRepository: Sendable {
    private let database: StorageDatabase

    public init(database: StorageDatabase) {
        self.database = database
    }

    public func get(_ key: String) throws -> String? {
        try database.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func set(_ key: String, value: String?) throws {
        try database.dbQueue.write { db in
            if let value {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                    arguments: [key, value]
                )
            } else {
                try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key])
            }
        }
    }

    public func all() throws -> [String: String] {
        try database.dbQueue.read { db in
            var out: [String: String] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
            for row in rows {
                let key: String = row["key"]
                let value: String? = row["value"]
                if let value { out[key] = value }
            }
            return out
        }
    }
}
