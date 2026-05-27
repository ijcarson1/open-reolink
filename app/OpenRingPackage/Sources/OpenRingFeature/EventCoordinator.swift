import Foundation
@preconcurrency import Combine
import ReolinkClient
import Storage
import UserNotifications

/// Per-camera authenticated event source.
public protocol CameraEventSource: Sendable {
    /// Long-running event stream — yields each motion / ring event as it
    /// arrives. The producer is responsible for renewing subscriptions and
    /// for surfacing `ONVIFError.notAuthorized` so the coordinator can
    /// apply lockout logic.
    func events(for camera: Camera, password: String) -> AsyncThrowingStream<ONVIFPullMessage, Error>
}

/// Domain-event surface for the feature layer (independent of ONVIF wire-shape).
public struct CameraEvent: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case motion, ring
    }
    public let id: UUID
    public let cameraId: UUID
    public let kind: Kind
    public let aiClass: String?
    public let topic: String
    public let occurredAt: Date

    public init(id: UUID = UUID(), cameraId: UUID, kind: Kind, aiClass: String?, topic: String, occurredAt: Date) {
        self.id = id
        self.cameraId = cameraId
        self.kind = kind
        self.aiClass = aiClass
        self.topic = topic
        self.occurredAt = occurredAt
    }
}

public struct CoordinatorClock: Sendable {
    public var now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }
}

/// Owns the cross-camera ONVIF subscription lifecycle (per ADR-0004) and
/// fans out events to the event repository + notification manager.
///
/// Lockout: 3 consecutive `notAuthorized` from a camera flips it to
/// "locked out" for `lockoutDuration` (default 5 minutes). The coordinator
/// stops polling that camera until the cooldown elapses.
public actor EventCoordinator {
    public static let lockoutThreshold: Int = 3
    public static let defaultLockoutDuration: TimeInterval = 5 * 60

    private let source: CameraEventSource
    private let events: EventRepository
    private let credentials: CredentialStore
    private let notifications: NotificationDispatching
    private let clock: CoordinatorClock
    private let lockoutDuration: TimeInterval

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var failureCounts: [UUID: Int] = [:]
    private var lockoutUntil: [UUID: Date] = [:]

    nonisolated(unsafe) public let eventsPublisher = PassthroughSubject<CameraEvent, Never>()

    public init(
        source: CameraEventSource,
        events: EventRepository,
        credentials: CredentialStore,
        notifications: NotificationDispatching,
        clock: CoordinatorClock = CoordinatorClock(),
        lockoutDuration: TimeInterval = EventCoordinator.defaultLockoutDuration
    ) {
        self.source = source
        self.events = events
        self.credentials = credentials
        self.notifications = notifications
        self.clock = clock
        self.lockoutDuration = lockoutDuration
    }

    public func start(cameras: [Camera]) async {
        for camera in cameras {
            startWatching(camera)
        }
    }

    public func stopAll() async {
        for (_, task) in tasks { task.cancel() }
        tasks.removeAll()
    }

    public func isLockedOut(cameraId: UUID, now: Date? = nil) -> Bool {
        guard let until = lockoutUntil[cameraId] else { return false }
        return (now ?? clock.now()) < until
    }

    public func failureCount(for cameraId: UUID) -> Int {
        failureCounts[cameraId] ?? 0
    }

    public func ingest(_ message: ONVIFPullMessage, for camera: Camera) async {
        let kind: CameraEvent.Kind
        let aiClass: String?
        switch message.classified {
        case .motion(let cls):
            kind = .motion
            aiClass = cls
        case .ring:
            kind = .ring
            aiClass = nil
        case .other:
            return
        }

        let event = CameraEvent(
            cameraId: camera.id,
            kind: kind,
            aiClass: aiClass,
            topic: message.topic,
            occurredAt: message.occurredAt
        )

        // Persist
        try? events.insert(StoredEvent(
            id: event.id,
            cameraId: event.cameraId,
            kind: StoredEvent.Kind(rawValue: kind.rawValue) ?? .motion,
            aiClass: aiClass,
            onvifTopic: message.topic,
            occurredAt: event.occurredAt
        ))

        // Notify per default policy: ring always; motion only with ai_class
        let shouldNotify = (kind == .ring) || (kind == .motion && aiClass != nil)
        if shouldNotify {
            await notifications.notify(event: event, cameraName: camera.displayName)
        }

        eventsPublisher.send(event)
    }

    public func recordFailure(for cameraId: UUID) {
        let count = (failureCounts[cameraId] ?? 0) + 1
        failureCounts[cameraId] = count
        if count >= Self.lockoutThreshold {
            lockoutUntil[cameraId] = clock.now().addingTimeInterval(lockoutDuration)
        }
    }

    public func recordSuccess(for cameraId: UUID) {
        failureCounts[cameraId] = 0
        lockoutUntil[cameraId] = nil
    }

    public func clearLockout(for cameraId: UUID) {
        failureCounts[cameraId] = 0
        lockoutUntil[cameraId] = nil
    }

    private func startWatching(_ camera: Camera) {
        guard tasks[camera.id] == nil else { return }
        guard let password = try? credentials.password(for: camera.id, role: .events) else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.source.events(for: camera, password: password)
                for try await message in stream {
                    if Task.isCancelled { return }
                    await self.recordSuccess(for: camera.id)
                    await self.ingest(message, for: camera)
                }
            } catch let error as ONVIFError where error == .notAuthorized {
                await self.recordFailure(for: camera.id)
            } catch {
                // Soft-fail; the source may retry on its own.
            }
        }
        tasks[camera.id] = task
    }
}
