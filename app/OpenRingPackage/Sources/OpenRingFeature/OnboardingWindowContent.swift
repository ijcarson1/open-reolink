import SwiftUI

/// Wrapper that hosts `OnboardingWizardView` in a dedicated NSWindow (opened
/// via `openWindow(id: "onboarding")`).
///
/// Sheets presented from inside a MenuBarExtra popover get dismissed when the
/// popover loses key focus (which happens on most clicks), so onboarding has
/// to be a real window.
public struct OnboardingWindowContent: View {
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
        OnboardingWizardView()
            .onDisappear {
                // Catch the close-via-window-button case so the popover doesn't
                // think a sheet is still presented.
            }
    }
}

/// Wrapper that hosts `SettingsSheet` (the form + Save/Cancel) in a dedicated
/// NSWindow (opened via `openWindow(id: "settings")`).
public struct SettingsWindowContent: View {
    public init() {}

    public var body: some View {
        SettingsSheet()
    }
}
