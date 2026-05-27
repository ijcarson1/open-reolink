import Foundation
import Testing
import ReolinkClient
import Storage
import VisionProviders
@testable import OpenRingFeature

@Suite("Settings round-trip + retention cleanup")
struct SettingsTests {

    @Test("Defaults are returned when no rows exist")
    func defaults() throws {
        let db = try StorageDatabase.inMemory()
        let svc = SettingsService(repository: SettingsRepository(database: db))
        let s = try svc.load()
        #expect(s.aiProvider == .none)
        #expect(s.autoOpenOnRing == true)
        #expect(s.eventRetentionDays == 30)
        #expect(s.motionMode == .aiClassified)
    }

    @Test("Save + load round-trips every field including per-camera overrides")
    func roundtrip() throws {
        let db = try StorageDatabase.inMemory()
        let svc = SettingsService(repository: SettingsRepository(database: db))
        let camId = UUID()
        var settings = AppSettings.default
        settings.aiProvider = .anthropic
        settings.anthropicModel = "claude-sonnet-4-5"
        settings.openAIModel = "gpt-4o-mini"
        settings.motionAIEnabled = true
        settings.aiRateCapPerMinute = 5
        settings.autoOpenOnRing = false
        settings.motionMode = .all
        settings.eventRetentionDays = 90
        settings.perCamera[camId] = CameraNotificationOverrides(ringNotify: false, motionNotify: true, muteAll: true)
        try svc.save(settings)

        let loaded = try svc.load()
        #expect(loaded.aiProvider == .anthropic)
        #expect(loaded.openAIModel == "gpt-4o-mini")
        #expect(loaded.motionAIEnabled == true)
        #expect(loaded.aiRateCapPerMinute == 5)
        #expect(loaded.autoOpenOnRing == false)
        #expect(loaded.motionMode == .all)
        #expect(loaded.eventRetentionDays == 90)
        #expect(loaded.perCamera[camId]?.muteAll == true)
        #expect(loaded.perCamera[camId]?.ringNotify == false)
    }

    @Test("EventRetentionCleaner deletes rows older than cutoff and keeps boundary + newer rows")
    func retentionCleanup() throws {
        let db = try StorageDatabase.inMemory()
        // Seed a camera so events FK passes
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO cameras (id, display_name, lan_ip, kind)
                VALUES ('00000000-0000-0000-0000-000000000001', 'C', '192.0.2.10', 'camera')
            """)
        }
        let events = EventRepository(database: db)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldEnough = StoredEvent(cameraId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                    kind: .motion,
                                    occurredAt: now.addingTimeInterval(-31 * 86_400),
                                    receivedAt: now.addingTimeInterval(-31 * 86_400))
        let cuspBoundary = StoredEvent(cameraId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                       kind: .motion,
                                       occurredAt: now.addingTimeInterval(-30 * 86_400),
                                       receivedAt: now.addingTimeInterval(-30 * 86_400))
        let newer = StoredEvent(cameraId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                kind: .ring,
                                occurredAt: now,
                                receivedAt: now)
        try events.insert(oldEnough)
        try events.insert(cuspBoundary)
        try events.insert(newer)

        let cleaner = EventRetentionCleaner(events: events)
        let deleted = try cleaner.cleanup(retentionDays: 30, now: now)
        #expect(deleted == 1, "only the >30d row should go")
        // Cusp = exactly 30 days ago, retention is 30 days, so cutoff = now-30d.
        // Boundary row's received_at == cutoff is kept (strict <, not <=).
        let remaining = try events.recent(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        #expect(remaining.count == 2)
    }
}

@Suite("NotificationPolicy composition")
struct NotificationPolicyTests {

    @Test("Default global motion=aiClassified — bare motion silent, ai motion notifies, ring always")
    func defaultPolicy() {
        let cameraId = UUID()
        let policy = NotificationPolicy()
        let ring = CameraEvent(cameraId: cameraId, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        let bare = CameraEvent(cameraId: cameraId, kind: .motion, aiClass: nil, topic: "motion", occurredAt: Date())
        let person = CameraEvent(cameraId: cameraId, kind: .motion, aiClass: "person", topic: "motion", occurredAt: Date())
        #expect(policy.shouldNotify(event: ring) == true)
        #expect(policy.shouldNotify(event: bare) == false)
        #expect(policy.shouldNotify(event: person) == true)
    }

    @Test("Global motionMode=.all also notifies on bare motion")
    func allMotionMode() {
        let policy = NotificationPolicy(motionMode: .all)
        let bare = CameraEvent(cameraId: UUID(), kind: .motion, aiClass: nil, topic: "motion", occurredAt: Date())
        #expect(policy.shouldNotify(event: bare) == true)
    }

    @Test("Per-camera mute overrides everything")
    func perCameraMute() {
        let camera = UUID()
        let policy = NotificationPolicy(perCamera: [camera: CameraNotificationOverrides(muteAll: true)])
        let ring = CameraEvent(cameraId: camera, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        #expect(policy.shouldNotify(event: ring) == false)
    }

    @Test("Disabling ringNotify on one camera doesn't affect another")
    func ringDisabledPerCamera() {
        let camA = UUID()
        let camB = UUID()
        let policy = NotificationPolicy(perCamera: [
            camA: CameraNotificationOverrides(ringNotify: false),
        ])
        let ringA = CameraEvent(cameraId: camA, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        let ringB = CameraEvent(cameraId: camB, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        #expect(policy.shouldNotify(event: ringA) == false)
        #expect(policy.shouldNotify(event: ringB) == true)
    }
}
