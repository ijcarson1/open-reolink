import Foundation
import Testing
import ReolinkClient
@testable import Storage

@Suite("CameraRepository")
struct CameraRepositoryTests {

    private func makeRepo() throws -> (StorageDatabase, CameraRepository) {
        let db = try StorageDatabase.inMemory()
        return (db, CameraRepository(database: db))
    }

    @Test("Insert + list round-trips full Camera (incl. capabilities JSON)")
    func insertList() throws {
        let (_, repo) = try makeRepo()
        let capabilities = CameraCapabilities(
            streamCodecs: ["h264", "h265"],
            rtspProfiles: ["main", "sub"],
            hasButtonPress: true,
            aiClasses: ["person", "vehicle"]
        )
        let camera = Camera(
            displayName: "Front door",
            lanIP: "192.0.2.20",
            kind: .doorbell,
            adminUsername: "admin",
            eventsUsername: "onvif",
            capabilities: capabilities,
            discoveredVia: .manual
        )
        try repo.insert(camera)
        let listed = try repo.list()
        #expect(listed.count == 1)
        let round = try #require(listed.first)
        #expect(round.displayName == "Front door")
        #expect(round.lanIP == "192.0.2.20")
        #expect(round.kind == .doorbell)
        #expect(round.eventsUsername == "onvif")
        #expect(round.discoveredVia == .manual)
        #expect(round.capabilities?.aiClasses == ["person", "vehicle"])
        #expect(round.capabilities?.hasButtonPress == true)
    }

    @Test("Get by ID returns the row, nil for unknown")
    func getById() throws {
        let (_, repo) = try makeRepo()
        let camera = Camera(displayName: "A", lanIP: "192.0.2.10")
        try repo.insert(camera)
        #expect(try repo.get(id: camera.id)?.displayName == "A")
        #expect(try repo.get(id: UUID()) == nil)
    }

    @Test("Update writes new values and refreshes updated_at")
    func update() throws {
        let (_, repo) = try makeRepo()
        var camera = Camera(displayName: "A", lanIP: "192.0.2.10")
        try repo.insert(camera)
        let original = try #require(try repo.get(id: camera.id))
        Thread.sleep(forTimeInterval: 1.1)
        camera = original
        camera.displayName = "B"
        try repo.update(camera)
        let updated = try #require(try repo.get(id: camera.id))
        #expect(updated.displayName == "B")
        #expect(updated.updatedAt > original.updatedAt)
    }

    @Test("Delete removes the row")
    func delete() throws {
        let (_, repo) = try makeRepo()
        let camera = Camera(displayName: "A", lanIP: "192.0.2.10")
        try repo.insert(camera)
        try repo.delete(id: camera.id)
        #expect(try repo.list().isEmpty)
    }
}
