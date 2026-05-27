import Foundation

/// Typed view of `cameras.capabilities_json` per ADR-0005.
///
/// Stored as TEXT in SQLite; decoded into this struct at read time. Adding a
/// new capability flag does NOT require a schema migration — only adding a
/// field here with a sensible default for older rows.
public struct CameraCapabilities: Codable, Hashable, Sendable {
    public var streamCodecs: [String]
    public var rtspProfiles: [String]
    public var hasPTZ: Bool
    public var hasSpotlight: Bool
    public var hasSiren: Bool
    public var hasAudioIn: Bool
    public var hasAudioOut: Bool
    public var hasButtonPress: Bool
    public var aiClasses: [String]

    public init(
        streamCodecs: [String] = [],
        rtspProfiles: [String] = [],
        hasPTZ: Bool = false,
        hasSpotlight: Bool = false,
        hasSiren: Bool = false,
        hasAudioIn: Bool = false,
        hasAudioOut: Bool = false,
        hasButtonPress: Bool = false,
        aiClasses: [String] = []
    ) {
        self.streamCodecs = streamCodecs
        self.rtspProfiles = rtspProfiles
        self.hasPTZ = hasPTZ
        self.hasSpotlight = hasSpotlight
        self.hasSiren = hasSiren
        self.hasAudioIn = hasAudioIn
        self.hasAudioOut = hasAudioOut
        self.hasButtonPress = hasButtonPress
        self.aiClasses = aiClasses
    }

    private enum CodingKeys: String, CodingKey {
        case streamCodecs = "stream_codecs"
        case rtspProfiles = "rtsp_profiles"
        case hasPTZ = "has_ptz"
        case hasSpotlight = "has_spotlight"
        case hasSiren = "has_siren"
        case hasAudioIn = "has_audio_in"
        case hasAudioOut = "has_audio_out"
        case hasButtonPress = "has_button_press"
        case aiClasses = "ai_classes"
    }
}
