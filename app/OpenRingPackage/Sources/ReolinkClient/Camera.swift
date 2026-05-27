import Foundation

public enum CameraKind: String, Codable, Sendable {
    case camera
    case doorbell
}

public enum CameraDiscoverySource: String, Codable, Sendable {
    case manual
    case onvifDiscovery = "onvif-discovery"
}

public struct Camera: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var lanIP: String
    public var kind: CameraKind
    public var cgiScheme: String
    public var cgiPort: Int
    public var rtspPort: Int
    public var onvifPort: Int
    public var model: String?
    public var firmwareVersion: String?
    public var adminUsername: String
    public var eventsUsername: String?
    public var capabilities: CameraCapabilities?
    public var discoveredVia: CameraDiscoverySource
    public var lastSeenAt: Date?
    public var isOnline: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        lanIP: String,
        kind: CameraKind = .camera,
        cgiScheme: String = "https",
        cgiPort: Int = 443,
        rtspPort: Int = 554,
        onvifPort: Int = 8000,
        model: String? = nil,
        firmwareVersion: String? = nil,
        adminUsername: String = "admin",
        eventsUsername: String? = nil,
        capabilities: CameraCapabilities? = nil,
        discoveredVia: CameraDiscoverySource = .manual,
        lastSeenAt: Date? = nil,
        isOnline: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.lanIP = lanIP
        self.kind = kind
        self.cgiScheme = cgiScheme
        self.cgiPort = cgiPort
        self.rtspPort = rtspPort
        self.onvifPort = onvifPort
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.adminUsername = adminUsername
        self.eventsUsername = eventsUsername
        self.capabilities = capabilities
        self.discoveredVia = discoveredVia
        self.lastSeenAt = lastSeenAt
        self.isOnline = isOnline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
