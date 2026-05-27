import Foundation
import Testing
import ReolinkClient
import Storage
@testable import OpenRingFeature

@Suite("EventCoordinator lockout + dispatch policy")
struct EventCoordinatorTests {

    @Test("3 consecutive notAuthorized failures flip lockout for ~5 minutes")
    func lockoutAfterThreeFailures() async {
        let camera = Camera(displayName: "Cam", lanIP: "192.0.2.10")
        let (coord, _, _, fixedClock) = makeCoordinator(for: camera)

        await coord.recordFailure(for: camera.id)
        await coord.recordFailure(for: camera.id)
        let lockedBefore3 = await coord.isLockedOut(cameraId: camera.id)
        #expect(lockedBefore3 == false)
        await coord.recordFailure(for: camera.id)
        let lockedAfter3 = await coord.isLockedOut(cameraId: camera.id)
        #expect(lockedAfter3 == true)

        let after5Minutes = await coord.isLockedOut(
            cameraId: camera.id,
            now: fixedClock.now().addingTimeInterval(EventCoordinator.defaultLockoutDuration + 1)
        )
        #expect(after5Minutes == false, "lockout should expire after 5min")
    }

    @Test("recordSuccess resets the failure counter and clears lockout")
    func successResetsLockout() async {
        let camera = Camera(displayName: "Cam", lanIP: "192.0.2.10")
        let (coord, _, _, _) = makeCoordinator(for: camera)
        for _ in 0..<3 { await coord.recordFailure(for: camera.id) }
        await coord.recordSuccess(for: camera.id)
        #expect(await coord.isLockedOut(cameraId: camera.id) == false)
        #expect(await coord.failureCount(for: camera.id) == 0)
    }

    @Test("ring events are persisted AND notified")
    func ringEventDispatch() async throws {
        let camera = Camera(displayName: "Front door", lanIP: "192.0.2.10", kind: .doorbell)
        let (coord, events, notifications, _) = makeCoordinator(for: camera)
        let message = ONVIFPullMessage(
            topic: "tns1:Device/Trigger/DigitalInput/VisitorPressedButton",
            classified: .ring,
            occurredAt: Date()
        )
        await coord.ingest(message, for: camera)
        // Allow the actor-based event flush to drain
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(try events.recent(for: camera.id).count == 1)
        let dispatched = await notifications.snapshot()
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.kind == .ring)
    }

    @Test("AI-classified motion events both persist and notify")
    func motionWithAIClassNotifies() async throws {
        let camera = Camera(displayName: "Garden", lanIP: "192.0.2.10")
        let (coord, events, notifications, _) = makeCoordinator(for: camera)
        let message = ONVIFPullMessage(
            topic: "tns1:RuleEngine/CellMotionDetector/Person",
            classified: .motion(aiClass: "person"),
            occurredAt: Date()
        )
        await coord.ingest(message, for: camera)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(try events.recent(for: camera.id).count == 1)
        let dispatched = await notifications.snapshot()
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.aiClass == "person")
    }

    @Test("Bare motion (no ai_class) persists but does NOT notify per default policy")
    func bareMotionSilent() async throws {
        let camera = Camera(displayName: "Garden", lanIP: "192.0.2.10")
        let (coord, events, notifications, _) = makeCoordinator(for: camera)
        let message = ONVIFPullMessage(
            topic: "tns1:VideoSource/MotionAlarm",
            classified: .motion(aiClass: nil),
            occurredAt: Date()
        )
        await coord.ingest(message, for: camera)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(try events.recent(for: camera.id).count == 1)
        let dispatched = await notifications.snapshot()
        #expect(dispatched.isEmpty, "bare motion must not notify under default policy")
    }

    // MARK: - factory

    private func makeCoordinator(for camera: Camera) -> (
        EventCoordinator, EventRepository, RecordingNotifications, CoordinatorClock
    ) {
        let db = try! StorageDatabase.inMemory()
        // Ensure the camera row exists so events FK passes
        let repo = CameraRepository(database: db)
        try? repo.insert(camera)
        let events = EventRepository(database: db)
        let credentials = CredentialStore(keychain: InMemoryKeychain(), service: "test")
        let notifications = RecordingNotifications()
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = CoordinatorClock { fixed }
        let source = StubEventSource()
        let coord = EventCoordinator(
            source: source,
            events: events,
            credentials: credentials,
            notifications: notifications,
            clock: clock
        )
        return (coord, events, notifications, clock)
    }
}

private struct StubEventSource: CameraEventSource {
    func events(for camera: Camera, password: String) -> AsyncThrowingStream<ONVIFPullMessage, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
}

actor RecordingNotifications: NotificationDispatching {
    private(set) var dispatched: [CameraEvent] = []

    nonisolated func requestAuthorizationIfNeeded() async {}
    nonisolated func notify(event: CameraEvent, cameraName: String) async {
        await record(event)
    }

    private func record(_ event: CameraEvent) {
        dispatched.append(event)
    }

    func snapshot() -> [CameraEvent] { dispatched }
}
