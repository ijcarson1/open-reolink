import Foundation

/// Authenticated ONVIF surface for Reolink cameras.
///
/// Used by:
/// - Slice 4's onboarding wizard (events-credentials verification, after
///   admin-creds verification via `ReolinkCGIClient.fetchSnapshot()`)
/// - Slice 5's `EventCoordinator` (Pull-Point Subscription lifecycle)
/// - Slice 6's AIGuard (capability detection for has_button_press → doorbell
///   semantics)
public final class ReolinkONVIFClient: @unchecked Sendable {
    public let camera: Camera
    private let password: String
    private let http: SoapHTTPClient

    public init(camera: Camera, eventsPassword: String, http: SoapHTTPClient? = nil) {
        self.camera = camera
        self.password = eventsPassword
        self.http = http ?? SoapHTTPClient(host: camera.lanIP)
    }

    public var deviceServiceURL: URL {
        URL(string: "http://\(camera.lanIP):\(camera.onvifPort)/onvif/device_service")!
    }

    public var eventsServiceURL: URL {
        URL(string: "http://\(camera.lanIP):\(camera.onvifPort)/onvif/event_service")!
    }

    public func verifyCredentials() async throws -> ONVIFDeviceInformation {
        try await getDeviceInformation()
    }

    public func getDeviceInformation() async throws -> ONVIFDeviceInformation {
        let digest = PasswordDigest.compute(password: password)
        let envelope = ONVIFSoap.envelope(
            action: .getDeviceInformation,
            to: deviceServiceURL,
            body: "<tds:GetDeviceInformation/>",
            username: camera.eventsUsername ?? "",
            digest: digest
        )
        let response = try await http.send(envelope: envelope, to: deviceServiceURL, action: .getDeviceInformation)
        return try ONVIFResponseParser.parseDeviceInformation(response)
    }

    public func createPullPointSubscription(timeoutSeconds: Int = 60) async throws -> ONVIFSubscriptionReference {
        let digest = PasswordDigest.compute(password: password)
        let envelope = ONVIFSoap.envelope(
            action: .createPullPointSubscription,
            to: eventsServiceURL,
            body: """
                <tev:CreatePullPointSubscription>
                  <tev:InitialTerminationTime>PT\(timeoutSeconds)S</tev:InitialTerminationTime>
                </tev:CreatePullPointSubscription>
                """,
            username: camera.eventsUsername ?? "",
            digest: digest
        )
        let response = try await http.send(envelope: envelope, to: eventsServiceURL, action: .createPullPointSubscription)
        return try ONVIFResponseParser.parseSubscriptionReference(response)
    }

    public func pullMessages(from subscription: ONVIFSubscriptionReference, timeoutSeconds: Int = 30) async throws -> [ONVIFPullMessage] {
        let digest = PasswordDigest.compute(password: password)
        let envelope = ONVIFSoap.envelope(
            action: .pullMessages,
            to: subscription.address,
            body: """
                <tev:PullMessages>
                  <tev:Timeout>PT\(timeoutSeconds)S</tev:Timeout>
                  <tev:MessageLimit>10</tev:MessageLimit>
                </tev:PullMessages>
                """,
            username: camera.eventsUsername ?? "",
            digest: digest,
            includeAddressing: true
        )
        let response = try await http.send(envelope: envelope, to: subscription.address, action: .pullMessages)
        return try ONVIFResponseParser.parsePullMessages(response)
    }

    public func renew(_ subscription: ONVIFSubscriptionReference, seconds: Int = 60) async throws {
        let digest = PasswordDigest.compute(password: password)
        let envelope = ONVIFSoap.envelope(
            action: .renew,
            to: subscription.address,
            body: "<wsnt:Renew><wsnt:TerminationTime>PT\(seconds)S</wsnt:TerminationTime></wsnt:Renew>",
            username: camera.eventsUsername ?? "",
            digest: digest,
            includeAddressing: true
        )
        _ = try await http.send(envelope: envelope, to: subscription.address, action: .renew)
    }

    public func unsubscribe(_ subscription: ONVIFSubscriptionReference) async throws {
        let digest = PasswordDigest.compute(password: password)
        let envelope = ONVIFSoap.envelope(
            action: .unsubscribe,
            to: subscription.address,
            body: "<wsnt:Unsubscribe/>",
            username: camera.eventsUsername ?? "",
            digest: digest,
            includeAddressing: true
        )
        _ = try await http.send(envelope: envelope, to: subscription.address, action: .unsubscribe)
    }
}
