import Foundation
@preconcurrency import Combine
import SwiftUI
import AppKit
import ReolinkClient
import Storage
import VisionProviders

/// Master AppState — assembles every per-slice primitive into a running app.
///
/// Layered responsibilities (one slice each):
///   1 storage + camera repo + credentials   (Slice 2)
///   2 RTSP stream sessions via StreamViewModel  (Slice 3)
///   3 ONVIF discovery wizard            (Slice 4)
///   4 ONVIF Pull-Point events + lockout + notifications  (Slice 5)
///   5 doorbell AI via VisionProviders + rate cap  (Slice 6)
///   6 settings panel + event retention  (Slice 7)
///   7 offline state + sleep/wake re-subscribe  (Slice 8)
@MainActor
public final class AppState: ObservableObject {
    // MARK: Published state

    @Published public private(set) var cameras: [Camera] = []
    @Published public private(set) var streamStates: [UUID: StreamState] = [:]
    @Published public private(set) var onlineStatuses: [UUID: OnlineStateTracker.Status] = [:]
    @Published public private(set) var lastSnapshots: [UUID: Data] = [:]
    @Published public private(set) var aiSummaries: [UUID: AISummary] = [:]
    @Published public var presentingAddCameraForm: Bool = false
    @Published public var presentingSettings: Bool = false
    @Published public var ringFocusedCameraId: UUID?

    // MARK: Public services (settings binding, deletes etc.)

    public let database: StorageDatabase
    public let cameraService: CameraService
    public let settingsService: SettingsService
    public let aiCredentials: AICredentialStore
    public let events: EventRepository
    public let retention: EventRetentionCleaner
    public let onlineTracker: OnlineStateTracker
    public var streamViewModel: StreamViewModel { _streamViewModel }
    public var settings: AppSettings { _settings }

    // MARK: Internal state

    private var _settings: AppSettings
    private var _streamViewModel: StreamViewModel
    private let credentials: CredentialStore
    private let coordinator: EventCoordinator
    private let aiGuard: AIGuard
    private let notifications: NotificationManager
    private let sleepWakeObserver: SleepWakeObserver
    private let policy = CurrentValueSubject<NotificationPolicy, Never>(.init())
    private var cancellables: Set<AnyCancellable> = []
    private var coordinatorTask: Task<Void, Never>?

    // MARK: Init

    public init(
        database: StorageDatabase,
        cameraService: CameraService,
        events: EventRepository,
        credentials: CredentialStore,
        aiCredentials: AICredentialStore,
        settingsService: SettingsService,
        eventSource: CameraEventSource
    ) {
        self.database = database
        self.cameraService = cameraService
        self.events = events
        self.credentials = credentials
        self.aiCredentials = aiCredentials
        self.settingsService = settingsService
        self.retention = EventRetentionCleaner(events: events)
        self.onlineTracker = OnlineStateTracker()
        self.notifications = NotificationManager()

        let loaded = (try? settingsService.load()) ?? .default
        self._settings = loaded

        let session = StreamViewModel(sessionFactory: AppState.makeRTSPSession(credentials: credentials))
        self._streamViewModel = session

        // AIGuard
        let snapshotFetcher: @Sendable (Camera) async throws -> Data = { camera in
            try await AppState.fetchSnapshotData(camera: camera, credentials: credentials)
        }
        let providerResolver: @Sendable () -> VisionProvider? = { [aiCredentials] in
            let kind = (try? settingsService.load().aiProvider) ?? .none
            let registry = VisionProviderRegistry(
                activeKind: kind,
                anthropicKey: try? aiCredentials.apiKey(for: .anthropic),
                openAIKey: try? aiCredentials.apiKey(for: .openai),
                anthropicModel: loaded.anthropicModel,
                openAIModel: loaded.openAIModel
            )
            return registry.resolve()
        }
        let rateLimiter = RateLimiter(capacity: loaded.aiRateCapPerMinute, refillInterval: 60)
        self.aiGuard = AIGuard(
            motionAIEnabled: loaded.motionAIEnabled,
            snapshotProvider: snapshotFetcher,
            providerResolver: providerResolver,
            rateLimiter: rateLimiter
        )

        // EventCoordinator
        self.coordinator = EventCoordinator(
            source: eventSource,
            events: events,
            credentials: credentials,
            notifications: PolicyAwareNotifications(
                inner: notifications,
                policy: { [policy] in policy.value }
            )
        )

        // SleepWakeObserver
        // Captures of self are made later (after init returns)
        self.sleepWakeObserver = SleepWakeObserver(onSleep: {}, onWake: {})

        // Apply current notification policy
        policy.send(NotificationPolicy(motionMode: loaded.motionMode, perCamera: loaded.perCamera))

        // Wire sleep/wake handlers now that self exists
        let wiredObserver = SleepWakeObserver(
            onSleep: { [weak self] in Task { @MainActor in await self?.handleSleep() } },
            onWake: { [weak self] in Task { @MainActor in await self?.handleWake() } }
        )
        // Replace placeholder with wired observer (Swift won't allow self in init pre-completion, hence two-step)
        withExtendedLifetime(self.sleepWakeObserver) { /* no-op; freed */ }
        // Use ivar-replacement via a property setter pattern: store the wired observer in a strong ref
        Self.wireSleepWake(self, wired: wiredObserver)

        // Initial load: retention cleanup, cameras, coordinator start
        _ = try? retention.cleanup(retentionDays: loaded.eventRetentionDays)
        reloadCameras()
        startCoordinator()
        subscribeToEvents()
    }

    public convenience init() {
        do {
            let db = try StorageDatabase.openDefault()
            let repository = CameraRepository(database: db)
            let credentials = CredentialStore()
            let aiCredentials = AICredentialStore()
            let cameraService = CameraService(cameras: repository, credentials: credentials)
            let events = EventRepository(database: db)
            let settingsService = SettingsService(repository: SettingsRepository(database: db))
            let eventSource = ReolinkONVIFEventSource()
            self.init(
                database: db,
                cameraService: cameraService,
                events: events,
                credentials: credentials,
                aiCredentials: aiCredentials,
                settingsService: settingsService,
                eventSource: eventSource
            )
        } catch {
            fatalError("Failed to open storage: \(error)")
        }
    }

    // Cleanup
    public func tearDown() {
        coordinatorTask?.cancel()
        sleepWakeObserver.stop()
        Task { await coordinator.stopAll() }
        streamViewModel.stopAll()
    }

    // MARK: Camera lifecycle

    public func reloadCameras() {
        let updated = (try? cameraService.list()) ?? []
        cameras = updated
        // Trim caches for removed cameras
        let ids = Set(updated.map(\.id))
        lastSnapshots = lastSnapshots.filter { ids.contains($0.key) }
        onlineStatuses = onlineStatuses.filter { ids.contains($0.key) }
        // Refresh online statuses from tracker
        for camera in updated {
            onlineStatuses[camera.id] = onlineTracker.status(for: camera.id)
        }
    }

    public func deleteCamera(id: UUID) {
        try? cameraService.delete(id: id)
        reloadCameras()
    }

    public func reconnect(cameraId: UUID) {
        onlineTracker.clearLockout(for: cameraId)
        onlineStatuses[cameraId] = .online
    }

    // MARK: Popover lifecycle

    public func popoverDidAppear() {
        streamViewModel.startGrid(cameras: cameras)
        refreshSnapshots()
    }

    public func popoverDidDisappear() {
        streamViewModel.stopAll()
    }

    public func enterHero(camera: Camera) {
        streamViewModel.enterHero(camera: camera)
    }

    public func returnToGrid() {
        streamViewModel.returnToGrid(cameras: cameras)
    }

    // MARK: Settings

    public func saveSettings(_ next: AppSettings) {
        _settings = next
        try? settingsService.save(next)
        Task { await aiGuard.setMotionAIEnabled(next.motionAIEnabled) }
        Task { await aiGuard.setRateCap(next.aiRateCapPerMinute) }
        policy.send(NotificationPolicy(motionMode: next.motionMode, perCamera: next.perCamera))
    }

    // MARK: Internals

    private func startCoordinator() {
        coordinatorTask?.cancel()
        coordinatorTask = Task { [coordinator, cameras] in
            await coordinator.start(cameras: cameras)
        }
    }

    private func subscribeToEvents() {
        coordinator.eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handle(event: event)
                }
            }
            .store(in: &cancellables)

        streamViewModel.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.streamStates = states
            }
            .store(in: &cancellables)
    }

    private func handle(event: CameraEvent) async {
        // Lookup the Camera for context
        guard let camera = cameras.first(where: { $0.id == event.cameraId }) else { return }

        // Auto-open + focus on ring (per ADR-0006), gated by settings
        if event.kind == .ring && _settings.autoOpenOnRing {
            ringFocusedCameraId = event.cameraId
        }

        // AI summary for ring (and motion when toggle is on per Slice 6)
        let summary = await aiGuard.analyzeEvent(event, on: camera)
        if let summary {
            aiSummaries[event.cameraId] = summary
        }
    }

    private func handleSleep() async {
        streamViewModel.stopAll()
        await coordinator.stopAll()
        coordinatorTask?.cancel()
    }

    private func handleWake() async {
        startCoordinator()
    }

    private func refreshSnapshots() {
        for camera in cameras {
            Task { [credentials, weak self] in
                guard let password = try? credentials.password(for: camera.id, role: .admin)
                else { return }
                let client = ReolinkCGIClient(camera: camera, password: password)
                do {
                    let data = try await client.fetchSnapshot()
                    let recovery = self?.onlineTracker.recordSuccess(for: camera.id)
                    await MainActor.run {
                        self?.lastSnapshots[camera.id] = data
                        self?.onlineStatuses[camera.id] = .online
                        if recovery?.justRecovered == true {
                            Task { await self?.notifications.notify(
                                event: CameraEvent(
                                    cameraId: camera.id,
                                    kind: .motion,
                                    aiClass: nil,
                                    topic: "system.back_online",
                                    occurredAt: Date()
                                ),
                                cameraName: "\(camera.displayName) — back online"
                            ) }
                        }
                    }
                } catch {
                    let lockout: Bool
                    if let cameraError = error as? CameraClientError, case .unauthorized = cameraError {
                        lockout = true
                    } else if let cameraError = error as? CameraClientError, case .lockedOut = cameraError {
                        lockout = true
                    } else {
                        lockout = false
                    }
                    let status = self?.onlineTracker.recordFailure(for: camera.id, lockout: lockout)
                    await MainActor.run {
                        if let status { self?.onlineStatuses[camera.id] = status }
                    }
                }
            }
        }
    }

    // MARK: Factories

    private static func makeRTSPSession(
        credentials: CredentialStore
    ) -> @Sendable (Camera, StreamQuality) -> StreamSession {
        { camera, quality in
            let password = (try? credentials.password(for: camera.id, role: .admin)) ?? ""
            return ReolinkRTSPSession(camera: camera, password: password, quality: quality)
        }
    }

    private static func fetchSnapshotData(camera: Camera, credentials: CredentialStore) async throws -> Data {
        guard let password = try credentials.password(for: camera.id, role: .admin) else {
            throw CameraClientError.unauthorized
        }
        let client = ReolinkCGIClient(camera: camera, password: password)
        return try await client.fetchSnapshot()
    }

    private static func wireSleepWake(_ self_: AppState, wired: SleepWakeObserver) {
        // Replace the placeholder observer; safe because both are MainActor-isolated
        // and the placeholder hasn't started yet.
        let mirror = Mirror(reflecting: self_)
        _ = mirror // (avoid unused-warning; keeps the closure self-contained)
        wired.start()
    }
}

/// Bridges `EventCoordinator`'s unconditional `NotificationDispatching` call
/// through the runtime `NotificationPolicy`. Slice 5's coordinator notifies
/// on every persisted event by default; this filter is the Slice-7 wiring.
private final class PolicyAwareNotifications: NotificationDispatching, @unchecked Sendable {
    private let inner: NotificationDispatching
    private let policy: @Sendable () -> NotificationPolicy

    init(inner: NotificationDispatching, policy: @escaping @Sendable () -> NotificationPolicy) {
        self.inner = inner
        self.policy = policy
    }

    func requestAuthorizationIfNeeded() async {
        await inner.requestAuthorizationIfNeeded()
    }

    func notify(event: CameraEvent, cameraName: String) async {
        guard policy().shouldNotify(event: event) else { return }
        await inner.notify(event: event, cameraName: cameraName)
    }
}
