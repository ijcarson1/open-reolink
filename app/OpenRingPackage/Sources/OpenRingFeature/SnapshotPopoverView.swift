import SwiftUI
import AppKit
import DesignSystem
import ReolinkClient

public struct SnapshotPopoverView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .frame(width: 480, height: 480)
        .onAppear { appState.startRefreshing() }
        .onDisappear { appState.stopRefreshing() }
        .sheet(isPresented: $appState.presentingAddCameraForm) {
            OnboardingWizardView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.cameras.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(appState.cameras) { camera in
                        CameraThumbnailView(camera: camera, snapshot: appState.snapshots[camera.id])
                            .contextMenu {
                                Button("Delete \(camera.displayName)", role: .destructive) {
                                    appState.deleteCamera(id: camera.id)
                                }
                            }
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
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
                .padding(10)
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
}

struct CameraThumbnailView: View {
    let camera: Camera
    let snapshot: AppState.SnapshotState?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.4)
                content
            }
            .aspectRatio(camera.kind == .doorbell ? 9.0/16.0 : 16.0/9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(camera.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot {
        case .none, .loading:
            ProgressView().tint(.white).controlSize(.small)
        case .ready(let jpeg, _):
            if let image = NSImage(data: jpeg) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .error(let message):
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
        }
    }
}
