import SwiftUI
import AppKit
import OpenRingFeature
import DesignSystem

@main
struct OpenRingApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            SnapshotPopoverView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
