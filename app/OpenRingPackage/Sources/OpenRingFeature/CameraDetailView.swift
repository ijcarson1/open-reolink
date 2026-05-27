import SwiftUI
import AppKit
import Combine
import ReolinkClient
import Storage

/// Live-view + camera-controls window. One per camera, opened from the popover
/// via `openWindow(value: cameraId)`.
///
/// Hosts a main-quality `ReolinkRTSPSession` that's independent of the
/// popover's grid sessions — so closing the popover doesn't kill the detail
/// window's stream, and vice versa.
public struct CameraDetailView: View {
    public let cameraId: UUID

    @EnvironmentObject private var appState: AppState
    @StateObject private var model = CameraDetailModel()
    @Environment(\.dismissWindow) private var dismissWindow

    public init(cameraId: UUID) {
        self.cameraId = cameraId
    }

    public var body: some View {
        Group {
            if let camera = appState.cameras.first(where: { $0.id == cameraId }) {
                detail(camera: camera)
            } else {
                missingCamera
            }
        }
        .navigationTitle(appState.cameras.first(where: { $0.id == cameraId })?.displayName ?? "Camera")
        .onDisappear { model.tearDown() }
    }

    private func detail(camera: Camera) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                streamSurface(for: camera)
                statusBadge
            }
            .frame(minWidth: 480, minHeight: 270)

            controlsStrip(camera: camera)
        }
        .onAppear { model.start(camera: camera, appState: appState) }
        .onChange(of: cameraId) { _, _ in
            model.tearDown()
            if let new = appState.cameras.first(where: { $0.id == cameraId }) {
                model.start(camera: new, appState: appState)
            }
        }
    }

    @ViewBuilder
    private func streamSurface(for camera: Camera) -> some View {
        switch model.state {
        case .failed:
            offlinePlaceholder(message: "Stream unavailable — check the camera is online", canReconnect: true)
        default:
            VLCVideoNSView { target in
                Task { await model.attach(target: target) }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let (label, color) = badge(for: model.state) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func badge(for state: StreamState) -> (String, Color)? {
        switch state {
        case .idle, .ended: return nil
        case .connecting: return ("Connecting", .blue)
        case .reconnecting: return ("Reconnecting", .orange)
        case .playing: return nil
        case .failed: return ("Offline", .red)
        }
    }

    private func offlinePlaceholder(message: String, canReconnect: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if canReconnect {
                Button("Reconnect") { model.reconnect() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func controlsStrip(camera: Camera) -> some View {
        HStack(spacing: 8) {
            controlButton(
                title: "Snapshot",
                systemImage: "camera",
                action: { model.captureSnapshot() }
            )
            controlButton(
                title: "Reconnect",
                systemImage: "arrow.clockwise",
                action: { model.reconnect() }
            )
            Divider().frame(height: 18)

            // Per ADR-0002 the following are deferred to v1.1. Buttons render
            // disabled so the affordance is visible — the v1.1 work just flips
            // them live.
            controlButton(
                title: "Spotlight",
                systemImage: "lightbulb",
                disabled: camera.capabilities?.hasSpotlight != true,
                action: {}
            )
            controlButton(
                title: "Siren",
                systemImage: "speaker.wave.3",
                disabled: camera.capabilities?.hasSiren != true,
                action: {}
            )
            controlButton(
                title: "Quick reply",
                systemImage: "text.bubble",
                disabled: camera.kind != .doorbell,
                action: {}
            )

            Spacer()

            if let saved = model.savedSnapshotPath {
                Text("Saved → \(saved)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func controlButton(
        title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 9))
            }
            .frame(minWidth: 56)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
    }

    private var missingCamera: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.video")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera not found")
                .font(.headline)
            Button("Close") { dismissWindow() }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
    }
}

@MainActor
final class CameraDetailModel: ObservableObject {
    @Published private(set) var state: StreamState = .idle
    @Published private(set) var savedSnapshotPath: String?

    private var session: ReolinkRTSPSession?
    private var cancellable: AnyCancellable?
    private var camera: Camera?
    private var appState: AppState?

    func start(camera: Camera, appState: AppState) {
        self.camera = camera
        self.appState = appState
        teardownSession()
        guard let password = (try? appState.cameraService.adminPassword(for: camera.id)) ?? nil else {
            state = .failed("No admin password stored for \(camera.displayName)")
            return
        }
        let session = ReolinkRTSPSession(camera: camera, password: password, quality: .main)
        self.session = session
        cancellable = session.state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
            }
    }

    func attach(target: VLCRenderTarget) async {
        guard let session else { return }
        do {
            try await session.attach(to: target)
        } catch {
            state = .failed("Could not attach to stream: \(error)")
        }
    }

    func reconnect() {
        guard let camera, let appState else { return }
        start(camera: camera, appState: appState)
    }

    func captureSnapshot() {
        guard let camera, let appState else { return }
        Task {
            do {
                guard let password = try appState.cameraService.adminPassword(for: camera.id) else { return }
                let client = ReolinkCGIClient(camera: camera, password: password)
                let jpeg = try await client.fetchSnapshot()
                let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let url = dir
                    .appendingPathComponent("open-reolink", isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let file = url.appendingPathComponent("\(camera.displayName)-\(Int(Date().timeIntervalSince1970)).jpg")
                try jpeg.write(to: file)
                await MainActor.run { savedSnapshotPath = file.path }
            } catch {
                await MainActor.run { savedSnapshotPath = "save failed: \(error.localizedDescription)" }
            }
        }
    }

    func tearDown() {
        cancellable?.cancel()
        cancellable = nil
        session?.stop()
        session = nil
    }

    private func teardownSession() {
        cancellable?.cancel()
        cancellable = nil
        session?.stop()
        session = nil
    }
}
