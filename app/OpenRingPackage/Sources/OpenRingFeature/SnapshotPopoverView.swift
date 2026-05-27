import SwiftUI
import AppKit
import ReolinkClient

public struct SnapshotPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

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
        .onChange(of: appState.presentingAddCameraForm) { _, present in
            if present {
                openOnboardingWindow()
                appState.presentingAddCameraForm = false
            }
        }
        .onChange(of: appState.presentingSettings) { _, present in
            if present {
                openSettingsWindow()
                appState.presentingSettings = false
            }
        }
        .onChange(of: appState.ringFocusedCameraId) { _, newValue in
            if let id = newValue,
               let camera = appState.cameras.first(where: { $0.id == id }) {
                appState.enterHero(camera: camera)
                appState.ringFocusedCameraId = nil
            }
        }
    }

    private func openOnboardingWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
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
                openOnboardingWindow()
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
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer()

                Button {
                    openOnboardingWindow()
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

/// Settings form with Save/Cancel footer — hosted by `SettingsWindowContent`
/// (a real NSWindow, not a sheet — sheets inside the MenuBarExtra popover
/// get dismissed when the popover loses key focus).
public struct SettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
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
                Button("Cancel") { dismissWindow(id: "settings") }
                Button("Save") {
                    try? viewModel.save()
                    appState.saveSettings(viewModel.settings)
                    appState.reloadCameras()
                    dismissWindow(id: "settings")
                }
                .keyboardShortcut(.return)
            }
            .padding(12)
        }
    }
}
