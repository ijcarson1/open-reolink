import Foundation
import Combine

/// VLCKit-backed `StreamSession` for Reolink RTSP — per ADR-0003.
///
/// **State of integration (Slice 3):** the protocol, state machine, and
/// reconnect scheduler are wired. The actual VLCKit playback is NOT linked yet
/// because VLCKit ships as a binary CocoaPod / xcframework rather than a
/// SwiftPM package — see the package-add path below. Until the binary is
/// available, `attach(...)` transitions the session to `.failed` with a clear
/// message instead of crashing, so the rest of the feature layer (and the
/// integration test using `FakeStreamSession`) is unblocked.
///
/// **To complete the wire-up (developer-local task):**
/// 1. Download the latest stable VLCKit xcframework from
///    https://download.videolan.org/pub/cocoapods/prod/ (or build from
///    https://code.videolan.org/videolan/VLCKit)
/// 2. Add it to the Xcode project as a dynamically-linked framework (LGPL §6
///    requires dynamic linkage; static linking is GPL-contaminating)
/// 3. Replace the `attach(...)` body below with VLCMediaPlayer construction:
///    - `let media = VLCMedia(url: rtspURL)`
///    - `media.addOptions([":rtsp-tcp": NSNull()])` (RTSP over TCP per ADR-0003)
///    - bind to `renderTarget`, observe state via VLCMediaPlayerDelegate, map
///      to `StreamState`
/// 4. Ship VLCKit's source / build-instructions per LGPL §6 — add a
///    `LICENSE-VLCKit` and a `NOTICE` file to repo root referencing the
///    upstream source URL
public final class ReolinkRTSPSession: StreamSession, @unchecked Sendable {
    public let camera: Camera
    public let quality: StreamQuality

    private let password: String
    private let subject = CurrentValueSubject<StreamState, Never>(.idle)
    private let scheduler = StreamReconnectScheduler()

    public var state: AnyPublisher<StreamState, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(camera: Camera, password: String, quality: StreamQuality) {
        self.camera = camera
        self.password = password
        self.quality = quality
    }

    public func attach(to renderTarget: StreamRenderTarget) async throws {
        guard let url = reolinkRTSPURL(for: camera, password: password, quality: quality) else {
            subject.send(.failed("Could not construct RTSP URL"))
            return
        }
        subject.send(.connecting)
        // TODO(slice-3 follow-up): wire VLCKit here per the docstring. Until then,
        // surface a clean failure state instead of silently doing nothing.
        _ = url
        subject.send(.failed("VLCKit not yet linked — see ReolinkRTSPSession.swift for setup"))
    }

    public func stop() {
        subject.send(.ended)
    }
}
