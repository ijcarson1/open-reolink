import SwiftUI
import ReolinkClient
import Storage
import VisionProviders

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var anthropicKey: String = ""
    @Published public var openAIKey: String = ""
    @Published public var cameras: [Camera] = []

    public let settingsService: SettingsService
    public let aiCredentials: AICredentialStore
    public let cameraService: CameraService
    public let events: EventRepository
    public let retention: EventRetentionCleaner

    public init(
        settings: AppSettings,
        settingsService: SettingsService,
        aiCredentials: AICredentialStore,
        cameraService: CameraService,
        events: EventRepository,
        retention: EventRetentionCleaner,
        cameras: [Camera]
    ) {
        self.settings = settings
        self.settingsService = settingsService
        self.aiCredentials = aiCredentials
        self.cameraService = cameraService
        self.events = events
        self.retention = retention
        self.cameras = cameras
        self.anthropicKey = (try? aiCredentials.apiKey(for: .anthropic)) ?? ""
        self.openAIKey = (try? aiCredentials.apiKey(for: .openai)) ?? ""
    }

    public func save() throws {
        try settingsService.save(settings)
        if !anthropicKey.isEmpty {
            try aiCredentials.setAPIKey(anthropicKey, for: .anthropic)
        }
        if !openAIKey.isEmpty {
            try aiCredentials.setAPIKey(openAIKey, for: .openai)
        }
    }

    public func clearAllEvents() throws {
        try events.deleteAll()
    }

    public func deleteCamera(id: UUID) throws {
        try cameraService.delete(id: id)
        cameras.removeAll { $0.id == id }
    }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            aiSection.tabItem { Label("AI", systemImage: "sparkles") }
            notificationsSection.tabItem { Label("Notifications", systemImage: "bell") }
            eventsSection.tabItem { Label("Events", systemImage: "list.bullet") }
            camerasSection.tabItem { Label("Cameras", systemImage: "video") }
        }
        .padding(16)
        .frame(width: 520, height: 520)
    }

    private var aiSection: some View {
        Form {
            Picker("Vision provider", selection: $model.settings.aiProvider) {
                ForEach(VisionProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            if model.settings.aiProvider != .none {
                let label = model.settings.aiProvider == .anthropic ? "Anthropic API key" : "OpenAI API key"
                SecureField(label, text: keyBinding)
                TextField(
                    model.settings.aiProvider == .anthropic ? "Anthropic model" : "OpenAI model",
                    text: modelBinding
                )
                Toggle("Run AI on classified motion events", isOn: $model.settings.motionAIEnabled)
                Stepper(
                    "AI rate cap: \(model.settings.aiRateCapPerMinute)/min per camera",
                    value: $model.settings.aiRateCapPerMinute,
                    in: 1...10
                )
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsSection: some View {
        Form {
            Toggle("Open popover automatically on ring", isOn: $model.settings.autoOpenOnRing)
            Picker("Motion notifications", selection: $model.settings.motionMode) {
                ForEach(MotionNotificationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            ForEach(model.cameras) { camera in
                Section(camera.displayName) {
                    let overrides = model.settings.perCamera[camera.id] ?? CameraNotificationOverrides()
                    Toggle("Ring notify", isOn: Binding(
                        get: { overrides.ringNotify },
                        set: { model.settings.perCamera[camera.id, default: CameraNotificationOverrides()].ringNotify = $0 }
                    ))
                    Toggle("Motion notify", isOn: Binding(
                        get: { overrides.motionNotify },
                        set: { model.settings.perCamera[camera.id, default: CameraNotificationOverrides()].motionNotify = $0 }
                    ))
                    Toggle("Mute all from this camera", isOn: Binding(
                        get: { overrides.muteAll },
                        set: { model.settings.perCamera[camera.id, default: CameraNotificationOverrides()].muteAll = $0 }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var eventsSection: some View {
        Form {
            Picker("Retention window", selection: $model.settings.eventRetentionDays) {
                ForEach([7, 30, 90], id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            Button("Clear all events now", role: .destructive) {
                try? model.clearAllEvents()
            }
        }
        .formStyle(.grouped)
    }

    private var camerasSection: some View {
        Form {
            ForEach(model.cameras) { camera in
                HStack {
                    VStack(alignment: .leading) {
                        Text(camera.displayName)
                        Text("\(camera.lanIP)  •  \(camera.kind.rawValue)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        try? model.deleteCamera(id: camera.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { model.settings.aiProvider == .anthropic ? model.anthropicKey : model.openAIKey },
            set: {
                if model.settings.aiProvider == .anthropic { model.anthropicKey = $0 }
                else { model.openAIKey = $0 }
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { model.settings.aiProvider == .anthropic ? model.settings.anthropicModel : model.settings.openAIModel },
            set: {
                if model.settings.aiProvider == .anthropic { model.settings.anthropicModel = $0 }
                else { model.settings.openAIModel = $0 }
            }
        )
    }
}
