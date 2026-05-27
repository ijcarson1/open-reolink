import Foundation
import SwiftUI
import ReolinkClient

/// Slice-1 app state.
///
/// Holds the single configured Camera (loaded from env/`.env` per `CameraConfig`)
/// and the latest JPEG snapshot. A background timer refreshes the snapshot every
/// 10 seconds while the popover is open. Slice 2 replaces this with persisted
/// multi-camera state from GRDB.
@MainActor
public final class AppState: ObservableObject {
    public enum Status: Sendable, Equatable {
        case unconfigured
        case loading
        case ready(jpeg: Data, fetchedAt: Date)
        case error(String)
    }

    @Published public private(set) var status: Status = .unconfigured
    @Published public private(set) var camera: Camera?

    private let client: CameraClient?
    private var refreshTask: Task<Void, Never>?

    public init() {
        if let cfg = CameraConfig.load() {
            self.camera = cfg.camera
            self.client = ReolinkCGIClient(camera: cfg.camera, password: cfg.password)
            self.status = .loading
        } else {
            self.camera = nil
            self.client = nil
            self.status = .unconfigured
        }
    }

    public func startRefreshing() {
        guard let client else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchOnce(using: client)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    public func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func fetchOnce(using client: CameraClient) async {
        do {
            let data = try await client.fetchSnapshot()
            self.status = .ready(jpeg: data, fetchedAt: Date())
        } catch let error as CameraClientError {
            self.status = .error(describe(error))
        } catch {
            self.status = .error(error.localizedDescription)
        }
    }

    private func describe(_ error: CameraClientError) -> String {
        switch error {
        case .unauthorized: return "Authentication failed — check REOLINK_USER / REOLINK_PASSWORD"
        case .lockedOut: return "Camera locked out by repeated auth failures — wait ~5 minutes"
        case .unreachable(let detail): return "Camera unreachable: \(detail)"
        case .unexpectedResponse(let status): return "Unexpected HTTP \(status) from camera"
        case .decoding(let detail): return "Bad response from camera: \(detail)"
        }
    }
}
