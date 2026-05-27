import Foundation
import UserNotifications

public protocol NotificationDispatching: Sendable {
    func requestAuthorizationIfNeeded() async
    func notify(event: CameraEvent, cameraName: String) async
}

/// Wraps `UNUserNotificationCenter`. Domain copy uses the vocabulary in
/// `CONTEXT.md` — "Doorbell rang", "Person detected at <camera>", etc.
public actor NotificationManager: NotificationDispatching {
    nonisolated public func requestAuthorizationIfNeeded() async {
        await requestAuthorizationIfNeededInternal()
    }

    nonisolated public func notify(event: CameraEvent, cameraName: String) async {
        await notifyInternal(event: event, cameraName: cameraName)
    }

    private let center: UNUserNotificationCenter
    private var hasRequestedAuth = false

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    private func requestAuthorizationIfNeededInternal() async {
        if hasRequestedAuth { return }
        hasRequestedAuth = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func notifyInternal(event: CameraEvent, cameraName: String) async {
        await requestAuthorizationIfNeededInternal()
        let content = UNMutableNotificationContent()
        switch event.kind {
        case .ring:
            content.title = "Doorbell rang"
            content.body = "Someone is at \(cameraName)"
        case .motion:
            if let aiClass = event.aiClass {
                content.title = "\(aiClass.capitalized) detected"
                content.body = "At \(cameraName)"
            } else {
                content.title = "Motion detected"
                content.body = "At \(cameraName)"
            }
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
