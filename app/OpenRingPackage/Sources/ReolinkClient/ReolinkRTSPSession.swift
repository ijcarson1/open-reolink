import Foundation
import Combine
import AppKit
import VLCKit

/// VLCKit-backed `StreamSession` for Reolink RTSP, per ADR-0003.
///
/// VLCKit is dynamically linked via SwiftPM `binaryTarget` (xcframework
/// staged by `scripts/setup-vlckit.sh`). LGPL §6 compliance:
/// `NOTICE-VLCKit.md` at the repo root.
///
/// Implementation details:
/// - RTSP over TCP via `:rtsp-tcp` (ADR-0003 — UDP is unreliable on Wi-Fi)
/// - Network caching tuned for low-latency LAN (300ms)
/// - State changes mapped from `VLCMediaPlayerState` to our `StreamState`
/// - Reconnect-on-error scheduling is handled at the next layer up via
///   `StreamReconnectScheduler` — `.failed` is the trigger
public final class ReolinkRTSPSession: NSObject, StreamSession, VLCMediaPlayerDelegate, @unchecked Sendable {
    public let camera: Camera
    public let quality: StreamQuality

    private let password: String
    private let subject = CurrentValueSubject<StreamState, Never>(.idle)
    private var player: VLCMediaPlayer?
    private var ownedRenderTarget: VLCRenderTarget?

    public var state: AnyPublisher<StreamState, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(camera: Camera, password: String, quality: StreamQuality) {
        self.camera = camera
        self.password = password
        self.quality = quality
        super.init()
    }

    public func attach(to renderTarget: StreamRenderTarget) async throws {
        guard let url = reolinkRTSPURL(for: camera, password: password, quality: quality) else {
            subject.send(.failed("Could not construct RTSP URL"))
            return
        }
        guard let target = renderTarget as? VLCRenderTarget else {
            subject.send(.failed("Unsupported render target — VLCRenderTarget required"))
            return
        }

        // Setup on the main thread — VLCVideoView is an AppKit NSView.
        await MainActor.run {
            let media = VLCMedia(url: url)
            media.addOption(":rtsp-tcp")
            media.addOption(":network-caching=300")

            let player = VLCMediaPlayer()
            player.media = media
            player.drawable = target.videoView
            player.delegate = self
            self.player = player
            self.ownedRenderTarget = target
            self.subject.send(.connecting)
            player.play()
        }
    }

    public func stop() {
        Task { @MainActor in
            self.player?.stop()
            self.player = nil
            self.ownedRenderTarget = nil
            self.subject.send(.ended)
        }
    }

    // MARK: - VLCMediaPlayerDelegate

    public func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        let mapped: StreamState
        switch player.state {
        case .opening, .buffering: mapped = .connecting
        case .playing: mapped = .playing
        case .paused: mapped = .playing // user-paused isn't a state we surface yet
        case .stopped, .ended: mapped = .ended
        case .error: mapped = .failed("VLCKit reported \(VLCMediaPlayerStateToString(player.state))")
        case .esAdded: return // intermediate
        @unknown default: return
        }
        subject.send(mapped)
    }
}

/// Concrete `StreamRenderTarget` that wraps a `VLCVideoView` for the feature
/// layer to insert into SwiftUI via an `NSViewRepresentable`.
///
/// `@unchecked Sendable` because every read/write of the underlying VLCVideoView
/// happens on the main thread (the SwiftUI representable always runs on
/// MainActor, and the session marshals its setup via `await MainActor.run`).
public final class VLCRenderTarget: StreamRenderTarget, @unchecked Sendable {
    public let videoView: VLCVideoView

    @MainActor
    public init() {
        let view = VLCVideoView(frame: .zero)
        view.fillScreen = true
        self.videoView = view
    }
}
