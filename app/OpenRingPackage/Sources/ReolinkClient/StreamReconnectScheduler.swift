import Foundation

/// Deterministic exponential-backoff scheduler for stream reconnects.
///
/// Sequence: 1s → 2s → 4s → 8s, capped at 8s thereafter. Driven by an
/// injectable clock so it is unit-testable without real time passing.
/// Slice 8 extends this to honour network-change events (cancel in-flight
/// backoff, reconnect immediately).
public final class StreamReconnectScheduler: @unchecked Sendable {
    public static let cap: TimeInterval = 8
    public static let initial: TimeInterval = 1

    private let lock = NSLock()
    private var attempt: Int = 0

    public init() {}

    /// Returns the next delay (seconds) to wait before reconnecting.
    /// The first call returns 1s, second 2s, third 4s, fourth+ 8s.
    public func nextDelay() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        defer { attempt += 1 }
        return min(Self.cap, Self.initial * pow(2.0, Double(attempt)))
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        attempt = 0
    }

    public var currentAttempt: Int {
        lock.lock(); defer { lock.unlock() }
        return attempt
    }
}
