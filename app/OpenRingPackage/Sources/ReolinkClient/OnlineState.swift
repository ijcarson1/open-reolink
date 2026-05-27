import Foundation

/// Per-camera reachability state — drives the offline tile + Settings → Cameras
/// indicators and the auth-lockout cooldown.
///
/// Pure state machine; the consumer (AppState in Slice 8) is responsible for
/// the actual probing (snapshot fetch, ONVIF Pull) and for surfacing the
/// "Camera back online" notification when `recordSuccess` flips state.
public final class OnlineStateTracker: @unchecked Sendable {
    public enum Status: Sendable, Equatable {
        case online
        case offline
        case lockedOut(until: Date)
    }

    public struct Clock: Sendable {
        public var now: @Sendable () -> Date
        public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }
    }

    /// `failureThreshold` consecutive snapshot/ONVIF failures → offline.
    public static let failureThreshold: Int = 3
    public static let lockoutDuration: TimeInterval = 5 * 60

    public let clock: Clock
    private let lock = NSLock()
    private var failures: [UUID: Int] = [:]
    private var statuses: [UUID: Status] = [:]
    private var pendingBackOnlineNotify: Set<UUID> = []

    public init(clock: Clock = Clock()) {
        self.clock = clock
    }

    public func status(for id: UUID) -> Status {
        lock.lock(); defer { lock.unlock() }
        return resolveLocked(id)
    }

    /// `wasOffline` set to true means the next consumer should also fire a
    /// one-shot "Camera back online" notification.
    @discardableResult
    public func recordSuccess(for id: UUID) -> (status: Status, justRecovered: Bool) {
        lock.lock(); defer { lock.unlock() }
        let previous = resolveLocked(id)
        failures[id] = 0
        statuses[id] = .online
        let recovered: Bool
        switch previous {
        case .offline, .lockedOut:
            recovered = pendingBackOnlineNotify.remove(id) != nil || true
            // Strip future-pending notify (we just fired)
            pendingBackOnlineNotify.remove(id)
        case .online:
            recovered = false
        }
        return (.online, recovered)
    }

    /// `lockout: true` means this failure was specifically a NotAuthorized
    /// after retries — applies the 5-minute lockout per ADR-0004 / CONTEXT.md.
    @discardableResult
    public func recordFailure(for id: UUID, lockout: Bool = false) -> Status {
        lock.lock(); defer { lock.unlock() }
        let count = (failures[id] ?? 0) + 1
        failures[id] = count
        if lockout {
            let until = clock.now().addingTimeInterval(Self.lockoutDuration)
            statuses[id] = .lockedOut(until: until)
            pendingBackOnlineNotify.insert(id)
        } else if count >= Self.failureThreshold {
            statuses[id] = .offline
            pendingBackOnlineNotify.insert(id)
        }
        return resolveLocked(id)
    }

    public func failureCount(for id: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        return failures[id] ?? 0
    }

    public func clearLockout(for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        if case .lockedOut = statuses[id] {
            statuses[id] = .offline
        }
    }

    private func resolveLocked(_ id: UUID) -> Status {
        guard let status = statuses[id] else { return .online }
        if case .lockedOut(let until) = status, clock.now() >= until {
            statuses[id] = .offline
            return .offline
        }
        return status
    }
}

/// Cap exponential reconnect backoff per the Slice 8 spec (10s → 30s → 60s,
/// capped 5min). Used by the offline-recovery loop.
public final class OfflineReconnectScheduler: @unchecked Sendable {
    public static let cap: TimeInterval = 5 * 60
    public static let initial: TimeInterval = 10
    public static let factor: Double = 3 // 10 → 30 → 60 → 180 → 300 → 300...

    private let lock = NSLock()
    private var attempt: Int = 0

    public init() {}

    public func nextDelay() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        defer { attempt += 1 }
        let next = Self.initial * pow(Self.factor, Double(attempt))
        return min(Self.cap, next)
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        attempt = 0
    }
}
