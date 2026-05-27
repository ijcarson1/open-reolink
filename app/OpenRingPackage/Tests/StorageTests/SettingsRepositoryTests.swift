import Foundation
import Testing
@testable import Storage

@Suite("SettingsRepository")
struct SettingsRepositoryTests {

    @Test("Set + get round-trip")
    func roundtrip() throws {
        let db = try StorageDatabase.inMemory()
        let repo = SettingsRepository(database: db)
        try repo.set("event_retention_days", value: "30")
        #expect(try repo.get("event_retention_days") == "30")
    }

    @Test("Set nil deletes the key")
    func setNilDeletes() throws {
        let db = try StorageDatabase.inMemory()
        let repo = SettingsRepository(database: db)
        try repo.set("k", value: "v")
        try repo.set("k", value: nil)
        #expect(try repo.get("k") == nil)
    }

    @Test("all() returns every non-nil setting")
    func all() throws {
        let db = try StorageDatabase.inMemory()
        let repo = SettingsRepository(database: db)
        try repo.set("a", value: "1")
        try repo.set("b", value: "2")
        let snap = try repo.all()
        #expect(snap == ["a": "1", "b": "2"])
    }
}
