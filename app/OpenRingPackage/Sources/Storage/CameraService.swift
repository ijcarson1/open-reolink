import Foundation
import ReolinkClient

/// Cross-store coordinator for Camera writes.
///
/// Every code path that mutates Cameras must go through this service —
/// `CameraRepository.delete` alone leaves orphaned Keychain entries (ADR-0005
/// requires the two `dev.open-reolink` entries to be removed when a camera
/// is deleted).
public final class CameraService: Sendable {
    private let cameras: CameraRepository
    private let credentials: CredentialStore

    public init(cameras: CameraRepository, credentials: CredentialStore) {
        self.cameras = cameras
        self.credentials = credentials
    }

    public func list() throws -> [Camera] {
        try cameras.list()
    }

    public func get(id: UUID) throws -> Camera? {
        try cameras.get(id: id)
    }

    /// Persists a camera and both passwords atomically *from the caller's
    /// perspective*. If Keychain writes fail after the row is inserted, the
    /// row is rolled back to keep the two stores aligned.
    public func add(
        camera: Camera,
        adminPassword: String,
        eventsPassword: String? = nil
    ) throws {
        try cameras.insert(camera)
        do {
            try credentials.setPassword(adminPassword, for: camera.id, role: .admin)
            if let eventsPassword {
                try credentials.setPassword(eventsPassword, for: camera.id, role: .events)
            }
        } catch {
            try? cameras.delete(id: camera.id)
            try? credentials.deleteAllPasswords(for: camera.id)
            throw error
        }
    }

    public func update(camera: Camera) throws {
        try cameras.update(camera)
    }

    public func delete(id: UUID) throws {
        try cameras.delete(id: id)
        try credentials.deleteAllPasswords(for: id)
    }

    public func adminPassword(for cameraId: UUID) throws -> String? {
        try credentials.password(for: cameraId, role: .admin)
    }

    public func eventsPassword(for cameraId: UUID) throws -> String? {
        try credentials.password(for: cameraId, role: .events)
    }
}
