import Foundation

public enum MotionNotificationMode: String, Codable, Sendable, CaseIterable {
    case none
    case aiClassified = "ai_classified"
    case all

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .aiClassified: return "AI-classified only"
        case .all: return "All motion"
        }
    }
}

public struct CameraNotificationOverrides: Codable, Sendable, Hashable {
    public var ringNotify: Bool
    public var motionNotify: Bool
    public var muteAll: Bool

    public init(ringNotify: Bool = true, motionNotify: Bool = true, muteAll: Bool = false) {
        self.ringNotify = ringNotify
        self.motionNotify = motionNotify
        self.muteAll = muteAll
    }
}

/// Decides whether a `CameraEvent` should fire a macOS notification.
///
/// Composes a global motion policy with per-camera overrides. Pure function —
/// trivially unit-testable. Slice 5's `EventCoordinator` calls
/// `shouldNotify(...)` before dispatching to `NotificationManager`.
public struct NotificationPolicy: Sendable, Equatable {
    public var motionMode: MotionNotificationMode
    public var perCamera: [UUID: CameraNotificationOverrides]

    public init(
        motionMode: MotionNotificationMode = .aiClassified,
        perCamera: [UUID: CameraNotificationOverrides] = [:]
    ) {
        self.motionMode = motionMode
        self.perCamera = perCamera
    }

    public func shouldNotify(event: CameraEvent) -> Bool {
        let override = perCamera[event.cameraId] ?? CameraNotificationOverrides()
        if override.muteAll { return false }
        switch event.kind {
        case .ring:
            return override.ringNotify
        case .motion:
            guard override.motionNotify else { return false }
            switch motionMode {
            case .none: return false
            case .aiClassified: return event.aiClass != nil
            case .all: return true
            }
        }
    }
}
