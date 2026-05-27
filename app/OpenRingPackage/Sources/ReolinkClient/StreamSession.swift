import Foundation
import Combine

public enum StreamQuality: String, Sendable, Codable {
    case main
    case sub
}

public enum StreamState: Sendable, Equatable {
    case idle
    case connecting
    case playing
    case reconnecting
    case failed(String)
    case ended
}

/// Vendor-agnostic live-video surface — per ADR-0001, the feature layer
/// talks to this protocol, not VLCKit (or any other backend) directly.
public protocol StreamSession: AnyObject, Sendable {
    var state: AnyPublisher<StreamState, Never> { get }
    var camera: Camera { get }
    var quality: StreamQuality { get }

    /// Attaches to a rendering surface and begins playback.
    func attach(to renderTarget: StreamRenderTarget) async throws

    /// Stops playback and detaches from the rendering surface.
    /// Calling stop on an already-stopped session is a no-op.
    func stop()
}

/// Opaque rendering surface — concrete impls choose between an
/// `NSView`, an `AVSampleBufferDisplayLayer`, etc. without leaking the
/// choice to callers. Concrete impls are responsible for marshalling their
/// AppKit-bound state onto the main thread (e.g. `VLCRenderTarget` is
/// `@MainActor` but exposes a `Sendable` surface so the session protocol
/// can be called from any actor).
public protocol StreamRenderTarget: AnyObject, Sendable {}

/// Builds the canonical Reolink RTSP URL for a given Camera and quality.
public func reolinkRTSPURL(for camera: Camera, password: String, quality: StreamQuality) -> URL? {
    var components = URLComponents()
    components.scheme = "rtsp"
    components.user = camera.adminUsername
    components.password = password
    components.host = camera.lanIP
    components.port = camera.rtspPort
    components.path = "/h264Preview_01_\(quality.rawValue)"
    return components.url
}
