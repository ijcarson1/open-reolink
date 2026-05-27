import SwiftUI
import AppKit
import DesignSystem
import ReolinkClient

/// Slice-1 popover.
///
/// Renders the latest JPEG snapshot from `AppState`. Refresh lifecycle is tied
/// to the popover's `onAppear` / `onDisappear` per ADR-0006 — streams (snapshot
/// polling, in this slice) live and die with the popover.
public struct SnapshotPopoverView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(width: 480, height: 320)
        .onAppear { appState.startRefreshing() }
        .onDisappear { appState.stopRefreshing() }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.status {
        case .unconfigured:
            unconfiguredView
        case .loading:
            ProgressView().tint(.white).scaleEffect(1.2)
        case .ready(let jpeg, let fetchedAt):
            snapshotView(jpeg: jpeg, fetchedAt: fetchedAt)
        case .error(let message):
            errorView(message: message)
        }
    }

    private var unconfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.5))
            Text("No camera configured")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Set REOLINK_IP / REOLINK_PASSWORD in the environment\nor in .env (see CameraConfig).")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func snapshotView(jpeg: Data, fetchedAt: Date) -> some View {
        VStack(spacing: 0) {
            if let image = NSImage(data: jpeg) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Could not decode snapshot")
                    .foregroundStyle(.white)
            }
            footer(camera: appState.camera, fetchedAt: fetchedAt)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func footer(camera: Camera?, fetchedAt: Date) -> some View {
        HStack {
            Text(camera?.displayName ?? "—")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(timeFormatter.string(from: fetchedAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }
}
