import Foundation
import Testing
import ReolinkClient
import Storage
@testable import OpenRingFeature

@Suite("AddCameraFormModel")
@MainActor
struct AddCameraFormTests {

    private func makeService(keychain: InMemoryKeychain = InMemoryKeychain()) throws -> (StorageDatabase, CameraService) {
        let db = try StorageDatabase.inMemory()
        let repo = CameraRepository(database: db)
        let credentials = CredentialStore(keychain: keychain, service: "test")
        return (db, CameraService(cameras: repo, credentials: credentials))
    }

    @Test("canSubmit is false until every required field is non-empty and IP is valid")
    func canSubmitGating() {
        let model = AddCameraFormModel()
        #expect(model.canSubmit == false)
        model.displayName = "Cam"
        model.lanIP = "not-an-ip"
        model.adminPassword = "x"
        model.eventsPassword = "y"
        #expect(model.canSubmit == false, "invalid IP should block submit")
        model.lanIP = "192.0.2.10"
        #expect(model.canSubmit == true)
        model.eventsUsername = ""
        #expect(model.canSubmit == false)
    }
}
