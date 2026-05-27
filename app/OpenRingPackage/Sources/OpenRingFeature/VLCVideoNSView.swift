import SwiftUI
import AppKit
import ReolinkClient

/// SwiftUI bridge for `VLCRenderTarget`.
///
/// Constructs a fresh render target on `makeNSView` and binds it to the
/// session via a callback. The caller's `onReady` closure receives the
/// target so it can pass it to `StreamSession.attach(to:)` — keeping all
/// playback logic out of the view layer.
public struct VLCVideoNSView: NSViewRepresentable {
    public let onReady: (VLCRenderTarget) -> Void

    public init(onReady: @escaping (VLCRenderTarget) -> Void) {
        self.onReady = onReady
    }

    public func makeNSView(context: Context) -> NSView {
        let target = VLCRenderTarget()
        context.coordinator.target = target
        DispatchQueue.main.async { onReady(target) }
        return target.videoView
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.target = nil
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var target: VLCRenderTarget?
    }
}
