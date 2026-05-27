import SwiftUI

// MARK: - Primary Button

public struct OpenReolinkPrimaryButton: View {
    private let title: String
    private let icon: String?
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: Layout.Button.iconSize))
                }
                Text(title)
                    .font(.OpenReolink.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Layout.Button.horizontalPadding)
            .padding(.vertical, Layout.Button.verticalPadding)
            .background(Color.OpenReolink.accent.brightness(isHovering ? 0.1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: Layout.Button.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: OpenReolinkAnimation.hoverDuration)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Secondary Button

public struct OpenReolinkSecondaryButton: View {
    private let title: String
    private let icon: String?
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: Layout.Button.iconSize))
                }
                Text(title)
                    .font(.OpenReolink.headline)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Layout.Button.horizontalPadding)
            .padding(.vertical, Layout.Button.verticalPadding)
            .background(isHovering ? Color.Semantic.hoverBackground : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Button.cornerRadius)
                    .stroke(Color.Semantic.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Layout.Button.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: OpenReolinkAnimation.hoverDuration)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Icon Button

public struct OpenReolinkIconButton: View {
    private let icon: String
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Layout.Button.iconSize))
                .foregroundStyle(.primary)
                .frame(width: Layout.Button.iconButtonSize, height: Layout.Button.iconButtonSize)
                .background(isHovering ? Color.Semantic.hoverBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Layout.Button.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: OpenReolinkAnimation.hoverDuration)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Toolbar Icon Button (smaller, for video overlays)

public struct OpenReolinkToolbarButton: View {
    private let icon: String
    private let isActive: Bool
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ icon: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.OpenReolink.accent : .white)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: OpenReolinkAnimation.hoverDuration)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ButtonsPreview: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Buttons")
                .font(.title2)

            HStack(spacing: Spacing.md) {
                OpenReolinkPrimaryButton("Live", icon: "video.fill") {}
                OpenReolinkPrimaryButton("Snooze") {}
            }

            HStack(spacing: Spacing.md) {
                OpenReolinkSecondaryButton("Motion: ON", icon: "bell.fill") {}
                OpenReolinkSecondaryButton("Settings", icon: "gearshape") {}
            }

            HStack(spacing: Spacing.sm) {
                OpenReolinkIconButton("xmark") {}
                OpenReolinkIconButton("pip.enter") {}
                OpenReolinkIconButton("speaker.slash.fill") {}
            }

            HStack(spacing: Spacing.xs) {
                OpenReolinkToolbarButton("speaker.slash.fill") {}
                OpenReolinkToolbarButton("pip.enter", isActive: true) {}
                OpenReolinkToolbarButton("xmark") {}
            }
            .padding(Spacing.sm)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview("Buttons") {
    ButtonsPreview()
}
#endif
