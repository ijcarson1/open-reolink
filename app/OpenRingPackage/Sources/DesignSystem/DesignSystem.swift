// DesignSystem - open-ring Design Tokens & Components
//
// Usage:
//   import DesignSystem
//
// Colors:
//   Color.OpenReolink.accent, Color.OpenReolink.ring, Color.OpenReolink.motion, Color.OpenReolink.package
//   Color.Semantic.textPrimary, Color.Semantic.hoverBackground
//
// Typography:
//   Font.OpenReolink.title, Font.OpenReolink.headline, Font.OpenReolink.body, Font.OpenReolink.timestamp
//
// Spacing:
//   Spacing.xs (4), Spacing.sm (8), Spacing.md (12), Spacing.lg (16), Spacing.xl (24)
//
// Layout:
//   Layout.Popover.width, Layout.Video.cornerRadius, Layout.Timeline.rowHeight
//
// Components:
//   OpenReolinkPrimaryButton, OpenReolinkSecondaryButton, OpenReolinkIconButton
//   EventIcon, StatusIndicator, LiveBadge

@_exported import SwiftUI

// Re-export all public types
public typealias DS = DesignSystem

public enum DesignSystem {
    public static let version = "0.1.0"
}
