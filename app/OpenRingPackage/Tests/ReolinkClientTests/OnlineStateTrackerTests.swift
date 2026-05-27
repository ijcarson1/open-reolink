import Foundation
import Testing
@testable import ReolinkClient

@Suite("OnlineStateTracker")
struct OnlineStateTrackerTests {

    @Test("3 consecutive failures flip to .offline; success restores to .online and signals justRecovered")
    func threeFailuresOffline() {
        let tracker = OnlineStateTracker()
        let id = UUID()
        _ = tracker.recordFailure(for: id)
        _ = tracker.recordFailure(for: id)
        #expect(tracker.status(for: id) == .online, "still online after 2 failures")
        _ = tracker.recordFailure(for: id)
        #expect(tracker.status(for: id) == .offline)
        let recovery = tracker.recordSuccess(for: id)
        #expect(recovery.status == .online)
        #expect(recovery.justRecovered == true, "back-online should signal once")
    }

    @Test("Subsequent success does NOT signal justRecovered again (one-shot)")
    func recoverySignalsOnce() {
        let tracker = OnlineStateTracker()
        let id = UUID()
        for _ in 0..<3 { _ = tracker.recordFailure(for: id) }
        let first = tracker.recordSuccess(for: id)
        let second = tracker.recordSuccess(for: id)
        #expect(first.justRecovered == true)
        #expect(second.justRecovered == false)
    }

    @Test("recordFailure(lockout: true) → .lockedOut with cooldown until clock advances 5 min")
    func lockout() {
        let now = MutableClockValue(Date(timeIntervalSince1970: 1_900_000_000))
        let tracker = OnlineStateTracker(clock: OnlineStateTracker.Clock(now: { now.value }))
        let id = UUID()
        let status = tracker.recordFailure(for: id, lockout: true)
        if case .lockedOut = status {
            #expect(true)
        } else {
            Issue.record("expected .lockedOut")
        }
        now.advance(by: OnlineStateTracker.lockoutDuration + 1)
        #expect(tracker.status(for: id) == .offline, "lockout should resolve to offline after cooldown")
    }
}

@Suite("OfflineReconnectScheduler")
struct OfflineReconnectSchedulerTests {

    @Test("Sequence is 10s → 30s → 90s → 180s capped at 300s (5 min)")
    func sequence() {
        let s = OfflineReconnectScheduler()
        #expect(s.nextDelay() == 10)
        #expect(s.nextDelay() == 30)
        #expect(s.nextDelay() == 90)
        #expect(s.nextDelay() == 270)
        #expect(s.nextDelay() == 300)
        #expect(s.nextDelay() == 300)
    }
}

final class MutableClockValue: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ start: Date) { date = start }
    var value: Date {
        lock.lock(); defer { lock.unlock() }
        return date
    }
    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        date = date.addingTimeInterval(interval)
    }
}
