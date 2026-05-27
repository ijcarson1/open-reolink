import Foundation
import SwiftUI
import ReolinkClient
import Storage

/// Slice-2 app state.
///
/// Loads Cameras from GRDB on launch, holds the latest snapshot per Camera,
/// and refreshes each Camera's snapshot every 10s while the popover is open
/// (per ADR-0006). The `CameraConfig` env-var loader from Slice 1 is gone —
/// Cameras come from `CameraRepository` now.
@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var cameras: [Camera] = []
    @Published public private(set) var snapshots: [UUID: SnapshotState] = [:]
    @Published public var presentingAddCameraForm: Bool = false
    @Published public var lastError: String?

    public let service: CameraService

    private let database: StorageDatabase
    private var refreshTask: Task<Void, Never>?

    public init(database: StorageDatabase, service: CameraService) {
        self.database = database
        self.service = service
        reload()
    }

    public convenience init() {
        do {
            let db = try StorageDatabase.openDefault()
            let repository = CameraRepository(database: db)
            let credentials = CredentialStore()
            let service = CameraService(cameras: repository, credentials: credentials)
            self.init(database: db, service: service)
        } catch {
            fatalError("Failed to open storage: \(error)")
        }
    }

    public func reload() {
        do {
            self.cameras = try service.list()
            // Trim snapshot cache for removed cameras
            let ids = Set(cameras.map(\.id))
            self.snapshots = snapshots.filter { ids.contains($0.key) }
        } catch {
            self.lastError = "Could not load cameras: \(error.localizedDescription)"
        }
    }

    public func deleteCamera(id: UUID) {
        do {
            try service.delete(id: id)
            reload()
        } catch {
            self.lastError = "Could not delete camera: \(error.localizedDescription)"
        }
    }

    public func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllOnce()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    public func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshAllOnce() async {
        let cams = cameras
        await withTaskGroup(of: (UUID, SnapshotState).self) { group in
            for camera in cams {
                group.addTask { [service] in
                    await Self.fetch(camera: camera, via: service)
                }
            }
            for await (id, state) in group {
                self.snapshots[id] = state
            }
        }
    }

    private nonisolated static func fetch(camera: Camera, via service: CameraService) async -> (UUID, SnapshotState) {
        do {
            guard let password = try service.adminPassword(for: camera.id) else {
                return (camera.id, .error("No admin password stored — re-add the camera"))
            }
            let client = ReolinkCGIClient(camera: camera, password: password)
            let data = try await client.fetchSnapshot()
            return (camera.id, .ready(jpeg: data, fetchedAt: Date()))
        } catch let error as CameraClientError {
            return (camera.id, .error(Self.describe(error)))
        } catch {
            return (camera.id, .error(error.localizedDescription))
        }
    }

    private nonisolated static func describe(_ error: CameraClientError) -> String {
        switch error {
        case .unauthorized: return "Auth failed"
        case .lockedOut: return "Locked out — wait ~5 min"
        case .unreachable: return "Unreachable"
        case .unexpectedResponse(let status): return "HTTP \(status)"
        case .decoding: return "Bad response"
        }
    }

    public enum SnapshotState: Sendable {
        case loading
        case ready(jpeg: Data, fetchedAt: Date)
        case error(String)
    }
}
