import SwiftUI
import AppKit
import OpenRingFeature
import DesignSystem

@main
struct OpenRingApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(OpenRingAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            SnapshotPopoverView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        // First-launch / Add-camera wizard. Opened via openWindow(id:) from the
        // popover. Sheets-in-popover dismiss when the popover loses focus, so the
        // wizard has to live in its own NSWindow.
        Window("Add a Reolink camera", id: "onboarding") {
            OnboardingWindowContent()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Settings live in their own NSWindow too.
        Window("open-reolink Settings", id: "settings") {
            SettingsWindowContent()
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// `LSUIElement` is set via INFOPLIST_KEY_LSUIElement in the build settings —
/// belt-and-braces, also flip the activation policy at launch so the dock icon
/// stays hidden even if a future build accidentally drops the plist key.
final class OpenRingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
