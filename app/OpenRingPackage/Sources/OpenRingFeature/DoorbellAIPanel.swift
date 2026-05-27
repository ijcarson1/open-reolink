import SwiftUI
import ReolinkClient

/// Overlay rendered on top of a doorbell `CameraTileView` after a ring event.
///
/// Per ADR-0007 / ADR-0002 this is doorbell-only in v1. The data comes from
/// `AIGuard.analyzeEvent(...)` — `.ok(text)` shows the summary, `.failure`
/// shows an error with a retry button, `.rateLimited` shows a "wait a moment"
/// state.
public struct DoorbellAIPanel: View {
    public let summary: AISummary
    public var onRetry: (() -> Void)?

    public init(summary: AISummary, onRetry: (() -> Void)? = nil) {
        self.summary = summary
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if case .failure = summary.outcome, let onRetry {
                    Button("Retry") { onRetry() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            switch summary.outcome {
            case .ok(let text):
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            case .failure(let message):
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            case .rateLimited:
                Text("Rate-limited — another summary will run after the cooldown.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        switch summary.outcome {
        case .ok: return "sparkles"
        case .failure: return "exclamationmark.triangle"
        case .rateLimited: return "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch summary.outcome {
        case .ok: return .yellow
        case .failure: return .red
        case .rateLimited: return .orange
        }
    }

    private var label: String {
        switch summary.outcome {
        case .ok: return "AI"
        case .failure: return "AI unavailable"
        case .rateLimited: return "AI cooled-down"
        }
    }
}
