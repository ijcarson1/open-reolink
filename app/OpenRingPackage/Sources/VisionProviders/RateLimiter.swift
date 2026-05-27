import Foundation

/// Per-key token-bucket rate limiter. Default cap: 1 call per minute per key
/// (per ADR-0007 and the Slice 6 AC). Drives the AIGuard's "don't burn the
/// provider quota on a stuck motion event" guarantee.
public final class RateLimiter: @unchecked Sendable {
    public struct Clock: Sendable {
        public var now: @Sendable () -> Date
        public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }
    }

    public private(set) var capacity: Int
    public private(set) var refillInterval: TimeInterval
    public let clock: Clock

    private let lock = NSLock()
    private var buckets: [String: (tokens: Int, lastRefill: Date)] = [:]

    public init(capacity: Int = 1, refillInterval: TimeInterval = 60, clock: Clock = Clock()) {
        self.capacity = capacity
        self.refillInterval = refillInterval
        self.clock = clock
    }

    public func setCapacity(_ newCapacity: Int) {
        lock.lock(); defer { lock.unlock() }
        capacity = max(1, newCapacity)
    }

    /// True if a token is available and was consumed.
    public func tryConsume(key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        refillLocked(key: key)
        let bucket = buckets[key] ?? (capacity, clock.now())
        if bucket.tokens > 0 {
            buckets[key] = (bucket.tokens - 1, bucket.lastRefill)
            return true
        }
        return false
    }

    /// For tests / settings: how many tokens are currently available for a key.
    public func availableTokens(for key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        refillLocked(key: key)
        return buckets[key]?.tokens ?? capacity
    }

    private func refillLocked(key: String) {
        let now = clock.now()
        guard let bucket = buckets[key] else {
            buckets[key] = (capacity, now)
            return
        }
        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        guard elapsed >= refillInterval else { return }
        let refills = Int(elapsed / refillInterval)
        let newTokens = min(capacity, bucket.tokens + refills)
        buckets[key] = (newTokens, bucket.lastRefill.addingTimeInterval(Double(refills) * refillInterval))
    }
}
