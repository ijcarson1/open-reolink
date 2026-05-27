import SwiftUI
import AppKit
import ReolinkClient

/// Renders a single Camera tile.
///
/// Live video via `VLCVideoNSView` once a `StreamSession` is attached.
/// Offline + locked-out states surface a placeholder with a Reconnect button
/// (per Slice 8). Aspect ratio is 9:16 for doorbells, 16:9 for cameras.
public struct CameraTileView: View {
    public let camera: Camera
    public let state: StreamState
    public let onlineStatus: OnlineStateTracker.Status
    public let lastSnapshot: Data?
    public let isHero: Bool
    public let audioEnabled: Bool
    public var onTap: (() -> Void)?
    public var onReconnect: (() -> Void)?
    public var onAttach: ((VLCRenderTarget) -> Void)?
    public var onToggleAudio: (() -> Void)?

    public init(
        camera: Camera,
        state: StreamState,
        onlineStatus: OnlineStateTracker.Status = .online,
        lastSnapshot: Data? = nil,
        isHero: Bool = false,
        audioEnabled: Bool = false,
        onTap: (() -> Void)? = nil,
        onReconnect: (() -> Void)? = nil,
        onAttach: ((VLCRenderTarget) -> Void)? = nil,
        onToggleAudio: (() -> Void)? = nil
    ) {
        self.camera = camera
        self.state = state
        self.onlineStatus = onlineStatus
        self.lastSnapshot = lastSnapshot
        self.isHero = isHero
        self.audioEnabled = audioEnabled
        self.onTap = onTap
        self.onReconnect = onReconnect
        self.onAttach = onAttach
        self.onToggleAudio = onToggleAudio
    }

    public var body: some View {
        ZStack {
            Color.black
            content
            connectionBadge
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: isHero ? 0 : 6))
        .overlay(alignment: .bottomLeading) {
            Text(camera.displayName)
                .font(.system(size: isHero ? 13 : 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            if let onToggleAudio, onlineStatus == .online {
                Button(action: onToggleAudio) {
                    Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .help(audioEnabled ? "Mute" : "Unmute")
                .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    public var aspectRatio: CGFloat {
        camera.kind == .doorbell ? 9.0 / 16.0 : 16.0 / 9.0
    }

    @ViewBuilder
    private var content: some View {
        switch onlineStatus {
        case .online:
            videoSurface
        case .offline:
            offlinePlaceholder(message: "Camera offline")
        case .lockedOut:
            offlinePlaceholder(message: "Camera locked — wait ~5 min before retrying")
        }
    }

    @ViewBuilder
    private var videoSurface: some View {
        ZStack {
            // Snapshot underlay — visible until VLC paints frames over it.
            // Keeps the tile from looking like a black hole during the ~1.5s
            // RTSP warm-up, and gives the user something to look at if the
            // live stream is permanently broken.
            if let snapshot = lastSnapshot, let image = NSImage(data: snapshot) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video")
                    .font(.system(size: isHero ? 44 : 22))
                    .foregroundStyle(.white.opacity(0.15))
            }

            if let onAttach {
                VLCVideoNSView(onReady: onAttach)
            }
        }
        .clipped()
    }

    private func offlinePlaceholder(message: String) -> some View {
        ZStack {
            if let snapshot = lastSnapshot, let image = NSImage(data: snapshot) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0)
                    .opacity(0.35)
            }
            VStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: isHero ? 28 : 18))
                    .foregroundStyle(.white.opacity(0.7))
                Text(message)
                    .font(.system(size: isHero ? 12 : 10, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                if onlineStatus == .offline, let onReconnect {
                    Button("Reconnect") { onReconnect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        if onlineStatus == .online, let (label, color) = badge(for: state) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.6), in: Capsule())
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func badge(for state: StreamState) -> (String, Color)? {
        switch state {
        case .idle, .playing, .ended: return nil
        case .connecting: return ("Connecting", .blue)
        case .reconnecting: return ("Reconnecting", .orange)
        case .failed: return ("Offline", .red)
        }
    }
}
