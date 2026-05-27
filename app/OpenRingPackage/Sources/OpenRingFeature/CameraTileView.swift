import SwiftUI
import AppKit
import ReolinkClient

/// Renders a single Camera tile.
///
/// Replaces Slice 1/2's snapshot-thumbnail view: the tile now binds to a
/// `StreamState` from `StreamViewModel`, and the visible badge reflects
/// connecting/reconnecting/failed states. Aspect ratio follows the Camera's
/// kind — 16:9 for cameras, 9:16 for doorbells (per ADR-0001's vendor-neutral
/// Camera type and the user-story "doorbell rendered in portrait").
public struct CameraTileView: View {
    public let camera: Camera
    public let state: StreamState
    public let isHero: Bool
    public var onTap: (() -> Void)? = nil

    public init(camera: Camera, state: StreamState, isHero: Bool = false, onTap: (() -> Void)? = nil) {
        self.camera = camera
        self.state = state
        self.isHero = isHero
        self.onTap = onTap
    }

    public var body: some View {
        ZStack {
            Color.black
            placeholder
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
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    public var aspectRatio: CGFloat {
        camera.kind == .doorbell ? 9.0 / 16.0 : 16.0 / 9.0
    }

    @ViewBuilder
    private var placeholder: some View {
        // Until VLCKit is linked, the stream layer falls through to a `.failed`
        // state and we render a static placeholder so the rest of the UI is
        // still inspectable. Slice 3 follow-up will replace this with the
        // VLCKit-backed view representable.
        Image(systemName: "video")
            .font(.system(size: isHero ? 44 : 22))
            .foregroundStyle(.white.opacity(0.15))
    }

    @ViewBuilder
    private var connectionBadge: some View {
        if let (label, color) = badge(for: state) {
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
