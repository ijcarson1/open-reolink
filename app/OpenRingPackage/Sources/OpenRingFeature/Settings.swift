import Foundation
import ReolinkClient
import Storage
import VisionProviders

/// Keys for the `settings` table per ADR-0005 / Slice 7's user-facing surface.
public enum SettingsKey {
    public static let aiProvider = "ai_provider"
    public static let aiModelAnthropic = "ai_model_anthropic"
    public static let aiModelOpenAI = "ai_model_openai"
    public static let motionAIEnabled = "motion_ai_enabled"
    public static let aiRateCap = "ai_rate_cap_per_minute"
    public static let autoOpenOnRing = "auto_open_on_ring"
    public static let motionNotificationMode = "motion_notification_mode"
    public static let eventRetentionDays = "event_retention_days"
    public static let perCameraOverrides = "per_camera_overrides_json"
}

public struct AppSettings: Sendable, Equatable {
    public var aiProvider: VisionProviderKind
    public var anthropicModel: String
    public var openAIModel: String
    public var motionAIEnabled: Bool
    public var aiRateCapPerMinute: Int
    public var autoOpenOnRing: Bool
    public var motionMode: MotionNotificationMode
    public var eventRetentionDays: Int
    public var perCamera: [UUID: CameraNotificationOverrides]

    public static let `default` = AppSettings(
        aiProvider: .none,
        anthropicModel: "claude-sonnet-4-5",
        openAIModel: "gpt-4o",
        motionAIEnabled: false,
        aiRateCapPerMinute: 1,
        autoOpenOnRing: true,
        motionMode: .aiClassified,
        eventRetentionDays: 30,
        perCamera: [:]
    )
}

/// Loads + persists `AppSettings` through the GRDB `SettingsRepository`.
public final class SettingsService: Sendable {
    private let repository: SettingsRepository

    public init(repository: SettingsRepository) {
        self.repository = repository
    }

    public func load() throws -> AppSettings {
        var s = AppSettings.default
        if let raw = try repository.get(SettingsKey.aiProvider),
           let kind = VisionProviderKind(rawValue: raw) {
            s.aiProvider = kind
        }
        if let m = try repository.get(SettingsKey.aiModelAnthropic), !m.isEmpty { s.anthropicModel = m }
        if let m = try repository.get(SettingsKey.aiModelOpenAI), !m.isEmpty { s.openAIModel = m }
        if let v = try repository.get(SettingsKey.motionAIEnabled) { s.motionAIEnabled = v == "1" }
        if let v = try repository.get(SettingsKey.aiRateCap), let n = Int(v) { s.aiRateCapPerMinute = max(1, n) }
        if let v = try repository.get(SettingsKey.autoOpenOnRing) { s.autoOpenOnRing = v == "1" }
        if let v = try repository.get(SettingsKey.motionNotificationMode), let mode = MotionNotificationMode(rawValue: v) {
            s.motionMode = mode
        }
        if let v = try repository.get(SettingsKey.eventRetentionDays), let n = Int(v) {
            s.eventRetentionDays = max(1, n)
        }
        if let json = try repository.get(SettingsKey.perCameraOverrides),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: CameraNotificationOverrides].self, from: data) {
            var byID: [UUID: CameraNotificationOverrides] = [:]
            for (k, v) in decoded {
                if let id = UUID(uuidString: k) { byID[id] = v }
            }
            s.perCamera = byID
        }
        return s
    }

    public func save(_ settings: AppSettings) throws {
        try repository.set(SettingsKey.aiProvider, value: settings.aiProvider.rawValue)
        try repository.set(SettingsKey.aiModelAnthropic, value: settings.anthropicModel)
        try repository.set(SettingsKey.aiModelOpenAI, value: settings.openAIModel)
        try repository.set(SettingsKey.motionAIEnabled, value: settings.motionAIEnabled ? "1" : "0")
        try repository.set(SettingsKey.aiRateCap, value: String(settings.aiRateCapPerMinute))
        try repository.set(SettingsKey.autoOpenOnRing, value: settings.autoOpenOnRing ? "1" : "0")
        try repository.set(SettingsKey.motionNotificationMode, value: settings.motionMode.rawValue)
        try repository.set(SettingsKey.eventRetentionDays, value: String(settings.eventRetentionDays))
        let stringMap = Dictionary(uniqueKeysWithValues: settings.perCamera.map { ($0.key.uuidString, $0.value) })
        if let json = try? JSONEncoder().encode(stringMap), let str = String(data: json, encoding: .utf8) {
            try repository.set(SettingsKey.perCameraOverrides, value: str)
        }
    }
}

/// Applies retention cleanup on launch.
public struct EventRetentionCleaner: Sendable {
    private let events: EventRepository

    public init(events: EventRepository) {
        self.events = events
    }

    /// Removes events with `received_at < now - retentionDays * 86400`.
    /// Returns the number of rows deleted (for tests).
    @discardableResult
    public func cleanup(retentionDays: Int, now: Date = Date()) throws -> Int {
        guard retentionDays > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return try events.deleteOlderThan(cutoff)
    }
}
