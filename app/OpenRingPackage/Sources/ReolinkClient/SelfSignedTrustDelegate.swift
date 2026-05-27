import Foundation

/// Trusts any server certificate when the host matches a configured IP.
///
/// Reolink cameras ship a self-signed certificate over HTTPS on the LAN
/// (per ADR-0004, HTTPS is required because HTTP can be disabled in firmware).
/// Standard URLSession TLS validation rejects the cert; this delegate accepts it
/// only for the configured host, leaving validation of any other host intact.
public final class SelfSignedTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let trustedHost: String

    public init(trustedHost: String) {
        self.trustedHost = trustedHost
    }

    /// Decides whether to override TLS validation for a given challenge.
    /// Pure function over the protection-space metadata — no `SecTrust` access —
    /// so it's unit-testable without real certificate material.
    public func shouldOverrideTrust(for space: URLProtectionSpace) -> Bool {
        space.authenticationMethod == NSURLAuthenticationMethodServerTrust
            && space.host == trustedHost
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard shouldOverrideTrust(for: challenge.protectionSpace),
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
