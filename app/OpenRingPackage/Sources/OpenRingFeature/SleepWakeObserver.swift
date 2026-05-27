import Foundation
import AppKit

/// Bridges `NSWorkspace` sleep/wake notifications into callbacks the
/// `EventCoordinator` and `StreamViewModel` consume.
///
/// On sleep: streams are stopped (Slice 3's `StreamViewModel.stopAll`),
/// ONVIF subscriptions are unsubscribed best-effort (Slice 5).
/// On wake: ONVIF subscriptions are re-opened; streams remain off until the
/// user re-opens the popover (per ADR-0006 — popover lifecycle).
public final class SleepWakeObserver: @unchecked Sendable {
    public typealias Handler = @Sendable () -> Void

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let onSleep: Handler
    private let onWake: Handler

    public init(onSleep: @escaping Handler, onWake: @escaping Handler) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [onSleep] _ in onSleep() }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [onWake] _ in onWake() }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let s = sleepObserver { center.removeObserver(s) }
        if let w = wakeObserver { center.removeObserver(w) }
        sleepObserver = nil
        wakeObserver = nil
    }

    deinit { stop() }
}
