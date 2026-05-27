import Foundation

public enum CameraKind: String, Codable, Sendable {
    case camera
    case doorbell
}

public struct Camera: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var lanIP: String
    public var kind: CameraKind
    public var cgiScheme: String
    public var cgiPort: Int
    public var adminUsername: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        lanIP: String,
        kind: CameraKind = .camera,
        cgiScheme: String = "https",
        cgiPort: Int = 443,
        adminUsername: String = "admin"
    ) {
        self.id = id
        self.displayName = displayName
        self.lanIP = lanIP
        self.kind = kind
        self.cgiScheme = cgiScheme
        self.cgiPort = cgiPort
        self.adminUsername = adminUsername
    }
}
