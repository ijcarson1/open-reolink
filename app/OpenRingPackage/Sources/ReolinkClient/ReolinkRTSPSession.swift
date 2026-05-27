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
/// - Auto-reconnect on unexpected `.stopped` / `.ended` / `.error` via
///   `StreamReconnectScheduler` (1s → 2s → 4s → 8s, capped at 8s)
public final class ReolinkRTSPSession: NSObject, StreamSession, VLCMediaPlayerDelegate, @unchecked Sendable {
    public let camera: Camera
    public let quality: StreamQuality

    private let password: String
    private let subject = CurrentValueSubject<StreamState, Never>(.idle)
    private var player: VLCMediaPlayer?
    private var ownedRenderTarget: VLCRenderTarget?
    private let scheduler = StreamReconnectScheduler()
    private var reconnectTask: Task<Void, Never>?
    private var hasReachedPlaying = false
    private var explicitlyStopped = false

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
        guard let target = renderTarget as? VLCRenderTarget else {
            subject.send(.failed("Unsupported render target — VLCRenderTarget required"))
            return
        }
        await MainActor.run {
            self.explicitlyStopped = false
            self.ownedRenderTarget = target
            self.startPlayback()
        }
    }

    public func stop() {
        Task { @MainActor in
            self.explicitlyStopped = true
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.player?.stop()
            self.player = nil
            self.ownedRenderTarget = nil
            self.subject.send(.ended)
        }
    }

    @MainActor
    private func startPlayback() {
        guard let target = ownedRenderTarget,
              let url = reolinkRTSPURL(for: camera, password: password, quality: quality)
        else {
            subject.send(.failed("Could not construct RTSP URL"))
            return
        }
        let media = VLCMedia(url: url)
        // Reolink RTSP tuning (LAN-stable settings, established by trial against
        // the Duo 3 PoE / E1 Zoom / Video Doorbell PoE on the test fleet).
        media.addOption(":rtsp-tcp")                       // ADR-0003: TCP not UDP
        media.addOption(":network-caching=1500")           // 1.5s buffer — was 300ms which starved the decoder on every Wi-Fi jitter
        media.addOption(":live-caching=1500")
        media.addOption(":rtsp-caching=1500")
        media.addOption(":rtsp-frame-buffer-size=500000")  // larger H.264 ring buffer for 4K Duo 3 PoE
        media.addOption(":clock-jitter=0")                 // LAN doesn't need jitter compensation
        media.addOption(":clock-synchro=0")                // skip PCR resync — Reolink doesn't honour it cleanly
        media.addOption(":sout-keep")                      // keep stream output alive across reconnects
        media.addOption(":rtp-timeout=60")                 // 60s RTP inactivity timeout (was libvlc default ~5s); Reolink sends keyframes every ~2s but drops idle conns aggressively

        let player = VLCMediaPlayer()
        player.media = media
        player.drawable = target.videoView
        player.delegate = self
        self.player = player
        self.subject.send(.connecting)
        player.play()
    }

    @MainActor
    private func scheduleReconnect(reason: String) {
        guard !explicitlyStopped, ownedRenderTarget != nil else { return }
        // Debounce: VLCKit can emit .stopped twice in rapid succession on a
        // single drop (once for the underlying access close, once for the
        // demux close). Without this guard we'd double-schedule.
        if reconnectTask != nil { return }
        let delay = scheduler.nextDelay()
        NSLog("openReolink: stream dropped for \(camera.displayName) (\(reason)); retrying in \(Int(delay))s")
        subject.send(.reconnecting)
        // Tear down the stale player explicitly so VLC drops its half-closed
        // TCP session before we open a new one.
        player?.stop()
        player = nil
        hasReachedPlaying = false
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.reconnectTask = nil
                self.startPlayback()
            }
        }
    }

    // MARK: - VLCMediaPlayerDelegate

    // VLCKit delivers delegate callbacks on the main thread (via the run-loop
    // NSNotificationCenter), so we capture the relevant state up-front
    // (Notification is not Sendable) and hop to MainActor for our own work.
    public func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        let snapshot = player.state
        MainActor.assumeIsolated {
            handleStateChange(snapshot)
        }
    }

    @MainActor
    private func handleStateChange(_ playerState: VLCMediaPlayerState) {
        switch playerState {
        case .opening, .buffering:
            subject.send(.connecting)
        case .playing:
            hasReachedPlaying = true
            scheduler.reset()
            subject.send(.playing)
        case .paused:
            subject.send(.playing)
        case .stopped, .ended:
            if explicitlyStopped {
                subject.send(.ended)
            } else {
                scheduleReconnect(reason: hasReachedPlaying ? "stopped after playing" : "stopped before playing")
            }
        case .error:
            let reason = VLCMediaPlayerStateToString(playerState)
            subject.send(.failed("VLCKit reported \(reason)"))
            scheduleReconnect(reason: "error: \(reason)")
        case .esAdded:
            return
        @unknown default:
            return
        }
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
