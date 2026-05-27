import SwiftUI
import AppKit
import ReolinkClient

public struct SnapshotPopoverView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            footer
        }
        .frame(width: 520, height: 560)
        .onAppear { appState.popoverDidAppear() }
        .onDisappear { appState.popoverDidDisappear() }
        .sheet(isPresented: $appState.presentingAddCameraForm) {
            OnboardingWizardView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.presentingSettings) {
            SettingsSheet()
                .environmentObject(appState)
        }
        .onChange(of: appState.ringFocusedCameraId) { _, newValue in
            if let id = newValue,
               let camera = appState.cameras.first(where: { $0.id == id }) {
                appState.enterHero(camera: camera)
                appState.ringFocusedCameraId = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.cameras.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(appState.cameras) { camera in
                        gridTile(for: camera)
                    }
                }
                .padding(10)
            }
        }
    }

    private func gridTile(for camera: Camera) -> some View {
        ZStack(alignment: .bottom) {
            CameraTileView(
                camera: camera,
                state: appState.streamStates[camera.id] ?? .idle,
                onlineStatus: appState.onlineStatuses[camera.id] ?? .online,
                lastSnapshot: appState.lastSnapshots[camera.id],
                isHero: false,
                onTap: { appState.enterHero(camera: camera) },
                onReconnect: { appState.reconnect(cameraId: camera.id) },
                onAttach: { target in
                    Task { [weak appState] in
                        guard let appState else { return }
                        let session = appState.streamViewModel
                        _ = session
                        // The view-model has already created the session; we hand the
                        // render target through the camera's session via attachTarget.
                        await appState.streamViewModel.attachRenderTarget(target, to: camera.id)
                    }
                }
            )

            if camera.kind == .doorbell, let summary = appState.aiSummaries[camera.id] {
                DoorbellAIPanel(summary: summary)
                    .padding(6)
            }
        }
        .contextMenu {
            Button("Delete \(camera.displayName)", role: .destructive) {
                appState.deleteCamera(id: camera.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.5))
            Text("No cameras configured")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Button {
                appState.presentingAddCameraForm = true
            } label: {
                Text("Add your first camera")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var footer: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    appState.presentingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer()

                Button {
                    appState.presentingAddCameraForm = true
                } label: {
                    Label("Add Camera", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }
}

/// Thin sheet wrapper that builds `SettingsViewModel` from `AppState`.
struct SettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let viewModel = SettingsViewModel(
            settings: appState.settings,
            settingsService: appState.settingsService,
            aiCredentials: appState.aiCredentials,
            cameraService: appState.cameraService,
            events: appState.events,
            retention: appState.retention,
            cameras: appState.cameras
        )

        VStack(alignment: .leading, spacing: 0) {
            SettingsView(model: viewModel)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    try? viewModel.save()
                    appState.saveSettings(viewModel.settings)
                    appState.reloadCameras()
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(12)
        }
    }
}
