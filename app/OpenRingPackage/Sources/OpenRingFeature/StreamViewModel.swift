import Foundation
import Combine
import SwiftUI
import ReolinkClient

/// Drives the multi-stream grid: which camera is "hero" (full-popover, main
/// quality, audio on) vs. which are tiles (sub quality, muted). The lifecycle
/// is bound to the popover's `onAppear`/`onDisappear` per ADR-0006 — sessions
/// die when the popover closes.
@MainActor
public final class StreamViewModel: ObservableObject {
    public enum Layout: Sendable, Equatable {
        case grid
        case hero(cameraId: UUID)
    }

    @Published public private(set) var layout: Layout = .grid
    @Published public private(set) var states: [UUID: StreamState] = [:]

    private let sessionFactory: @Sendable (Camera, StreamQuality) -> StreamSession
    private var sessions: [UUID: StreamSession] = [:]
    private var cancellables: [UUID: AnyCancellable] = [:]

    public init(sessionFactory: @escaping @Sendable (Camera, StreamQuality) -> StreamSession) {
        self.sessionFactory = sessionFactory
    }

    /// Starts a sub-quality session per camera (the grid baseline).
    public func startGrid(cameras: [Camera]) {
        layout = .grid
        // Stop any sessions for cameras that are no longer present
        let activeIDs = Set(cameras.map(\.id))
        for (id, _) in sessions where !activeIDs.contains(id) {
            stopSession(id: id)
        }
        for camera in cameras where sessions[camera.id] == nil {
            startSession(for: camera, quality: .sub)
        }
    }

    /// Switches the focused camera to a main-quality session, keeping the
    /// others alive at sub quality.
    public func enterHero(camera: Camera) {
        layout = .hero(cameraId: camera.id)
        // Swap that one session to main quality
        stopSession(id: camera.id)
        startSession(for: camera, quality: .main)
    }

    /// Drops back to the all-grid layout, restoring the previously-hero camera
    /// to sub quality.
    public func returnToGrid(cameras: [Camera]) {
        guard case .hero(let id) = layout, let camera = cameras.first(where: { $0.id == id }) else {
            layout = .grid
            return
        }
        layout = .grid
        stopSession(id: camera.id)
        startSession(for: camera, quality: .sub)
    }

    /// Stops every session — invoked from the popover's `onDisappear`.
    public func stopAll() {
        for id in Array(sessions.keys) {
            stopSession(id: id)
        }
    }

    /// True when the camera is the current hero target — used by the view to
    /// route audio (audio plays from hero only).
    public func isHero(cameraId: UUID) -> Bool {
        if case .hero(let id) = layout { return id == cameraId }
        return false
    }

    // MARK: - Session lifecycle

    private func startSession(for camera: Camera, quality: StreamQuality) {
        let session = sessionFactory(camera, quality)
        sessions[camera.id] = session
        cancellables[camera.id] = session.state.sink { [weak self] state in
            Task { @MainActor in
                self?.states[camera.id] = state
            }
        }
    }

    private func stopSession(id: UUID) {
        sessions[id]?.stop()
        sessions[id] = nil
        cancellables[id]?.cancel()
        cancellables[id] = nil
        states[id] = nil
    }

    /// Hands a fresh render target (built by a SwiftUI representable) to the
    /// session for that camera so playback can begin. Creates the session on
    /// demand if it doesn't already exist — covers the case where the tile
    /// appears before `startGrid(...)` runs (e.g. when a new camera lands
    /// while the popover is already open).
    public func attachRenderTarget(_ target: StreamRenderTarget, to camera: Camera) async {
        if sessions[camera.id] == nil {
            startSession(for: camera, quality: .sub)
        }
        guard let session = sessions[camera.id] else {
            NSLog("openReolink: attachRenderTarget failed — no session for \(camera.displayName)")
            return
        }
        do {
            try await session.attach(to: target)
        } catch {
            NSLog("openReolink: session.attach failed for \(camera.displayName): \(error)")
        }
    }

    /// Mute / unmute the popover tile's session for a given camera.
    public func setAudio(enabled: Bool, for cameraId: UUID) {
        (sessions[cameraId] as? ReolinkRTSPSession)?.setAudioEnabled(enabled)
    }

    // Test-only accessors — needed by integration tests to inspect lifecycle.
    public func activeSessionCount() -> Int { sessions.count }
    public func quality(for cameraId: UUID) -> StreamQuality? {
        sessions[cameraId]?.quality
    }
}
