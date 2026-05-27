import Foundation
import Testing
@testable import Storage

@Suite("CredentialStore + CameraService cascade")
struct CredentialStoreTests {

    @Test("Stores passwords keyed by <cameraId>.admin and <cameraId>.events")
    func roleKeyedStorage() throws {
        let keychain = InMemoryKeychain()
        let store = CredentialStore(keychain: keychain, service: "test")
        let id = UUID()

        try store.setPassword("admin-pw", for: id, role: .admin)
        try store.setPassword("events-pw", for: id, role: .events)

        #expect(try store.password(for: id, role: .admin) == "admin-pw")
        #expect(try store.password(for: id, role: .events) == "events-pw")

        let snapshot = keychain.snapshot()
        #expect(snapshot["\(id.uuidString).admin"] == "admin-pw")
        #expect(snapshot["\(id.uuidString).events"] == "events-pw")
    }

    @Test("Reading a missing entry returns nil rather than throwing")
    func missingReturnsNil() throws {
        let store = CredentialStore(keychain: InMemoryKeychain(), service: "test")
        #expect(try store.password(for: UUID(), role: .admin) == nil)
    }

    @Test("deleteAllPasswords removes both roles, leaving other cameras alone")
    func deleteAllPasswords() throws {
        let keychain = InMemoryKeychain()
        let store = CredentialStore(keychain: keychain, service: "test")
        let camA = UUID()
        let camB = UUID()
        try store.setPassword("a-admin", for: camA, role: .admin)
        try store.setPassword("a-events", for: camA, role: .events)
        try store.setPassword("b-admin", for: camB, role: .admin)
        try store.setPassword("b-events", for: camB, role: .events)

        try store.deleteAllPasswords(for: camA)

        #expect(try store.password(for: camA, role: .admin) == nil)
        #expect(try store.password(for: camA, role: .events) == nil)
        #expect(try store.password(for: camB, role: .admin) == "b-admin")
        #expect(try store.password(for: camB, role: .events) == "b-events")
    }

    @Test("CameraService.delete removes both DB row and Keychain entries")
    func serviceDeleteCascades() throws {
        let database = try StorageDatabase.inMemory()
        let repo = CameraRepository(database: database)
        let keychain = InMemoryKeychain()
        let credentials = CredentialStore(keychain: keychain, service: "test")
        let service = CameraService(cameras: repo, credentials: credentials)

        let camera = ReolinkCameraFactory.make(displayName: "Cam")
        try service.add(camera: camera, adminPassword: "a", eventsPassword: "e")

        try service.delete(id: camera.id)

        #expect(try repo.get(id: camera.id) == nil)
        #expect(try credentials.password(for: camera.id, role: .admin) == nil)
        #expect(try credentials.password(for: camera.id, role: .events) == nil)
    }

    @Test("CameraService.add rolls back the camera row when Keychain write fails")
    func addRollsBackOnFailure() throws {
        let database = try StorageDatabase.inMemory()
        let repo = CameraRepository(database: database)
        let keychain = FailingKeychain()
        let credentials = CredentialStore(keychain: keychain, service: "test")
        let service = CameraService(cameras: repo, credentials: credentials)
        let camera = ReolinkCameraFactory.make(displayName: "Cam")

        #expect(throws: (any Error).self) {
            try service.add(camera: camera, adminPassword: "a", eventsPassword: "e")
        }
        #expect(try repo.get(id: camera.id) == nil)
    }
}

import ReolinkClient

private enum ReolinkCameraFactory {
    static func make(displayName: String) -> Camera {
        Camera(displayName: displayName, lanIP: "192.0.2.10", adminUsername: "admin", eventsUsername: "onvif")
    }
}

private final class FailingKeychain: KeychainAccessing, @unchecked Sendable {
    func read(account: String, service: String) throws -> String? { nil }
    func write(account: String, service: String, value: String) throws { throw KeychainError.osStatus(-1) }
    func delete(account: String, service: String) throws {}
    func deleteAll(service: String) throws {}
}
