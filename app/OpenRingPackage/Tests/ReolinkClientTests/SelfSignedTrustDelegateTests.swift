import Foundation
import Testing
@testable import ReolinkClient

@Suite("SelfSignedTrustDelegate")
struct SelfSignedTrustDelegateTests {

    @Test("Overrides trust for the configured host on a server-trust challenge")
    func acceptsTrustedHost() {
        let delegate = SelfSignedTrustDelegate(trustedHost: "192.0.2.10")
        let space = URLProtectionSpace(
            host: "192.0.2.10",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        #expect(delegate.shouldOverrideTrust(for: space) == true)
    }

    @Test("Defers to default handling for a different host")
    func defersForOtherHost() async throws {
        let delegate = SelfSignedTrustDelegate(trustedHost: "192.0.2.10")
        let session = URLSession(configuration: .ephemeral)
        let space = URLProtectionSpace(
            host: "evil.example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = TestAuthChallenge.make(protectionSpace: space)
        let (disposition, credential) = await invoke(delegate, session: session, challenge: challenge)
        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }

    @Test("Defers to default handling for non-server-trust authentication methods")
    func defersForOtherAuthMethods() async throws {
        let delegate = SelfSignedTrustDelegate(trustedHost: "192.0.2.10")
        let session = URLSession(configuration: .ephemeral)
        let space = URLProtectionSpace(
            host: "192.0.2.10",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let challenge = TestAuthChallenge.make(protectionSpace: space)
        let (disposition, _) = await invoke(delegate, session: session, challenge: challenge)
        #expect(disposition == .performDefaultHandling)
    }

    private func invoke(
        _ delegate: SelfSignedTrustDelegate,
        session: URLSession,
        challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await withCheckedContinuation { cont in
            delegate.urlSession(session, didReceive: challenge) { d, c in
                cont.resume(returning: (d, c))
            }
        }
    }
}

private enum TestAuthChallenge {
    static func make(protectionSpace: URLProtectionSpace) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: NoOpSender()
        )
    }
}

private final class NoOpSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
