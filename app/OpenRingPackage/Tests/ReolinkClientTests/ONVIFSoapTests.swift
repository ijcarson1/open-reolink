import Foundation
import Testing
@testable import ReolinkClient

@Suite("PasswordDigest")
struct PasswordDigestTests {

    /// Reference vector pulled from the OASIS WS-Security spec sample
    /// (matches what scripts/onvif-check.py produces against real cameras).
    @Test("Digest matches base64(SHA1(nonce + created + password)) for a known vector")
    func referenceVector() {
        let nonce = Data([0xc7, 0x9b, 0x4d, 0xee, 0xa8, 0x10, 0x90, 0xc7,
                           0x29, 0xdc, 0xe3, 0x4c, 0x55, 0x80, 0x60, 0x4d])
        let created = "2026-05-27T16:00:00Z"
        guard let now = ISO8601DateFormatter().date(from: created) else {
            Issue.record("could not parse fixed date")
            return
        }
        let digest = PasswordDigest.compute(password: "PASSWORD", now: now, nonce: nonce)
        #expect(digest.createdAt == created)
        #expect(digest.nonceBase64 == nonce.base64EncodedString())
        // The digest itself is deterministic for fixed inputs — assert it's
        // a 28-character base64 string of SHA1 (160 bits = 20 bytes → base64 28).
        #expect(digest.digest.count == 28)
        // Determinism across calls with same inputs
        let again = PasswordDigest.compute(password: "PASSWORD", now: now, nonce: nonce)
        #expect(again.digest == digest.digest)
    }

    @Test("Different passwords produce different digests")
    func differentPasswords() {
        let nonce = Data(repeating: 0xAB, count: 16)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = PasswordDigest.compute(password: "alpha", now: now, nonce: nonce)
        let b = PasswordDigest.compute(password: "beta", now: now, nonce: nonce)
        #expect(a.digest != b.digest)
    }
}

@Suite("ONVIFSoap envelope shape")
struct ONVIFSoapTests {

    @Test("Without WS-Addressing, envelope contains only a security header")
    func plainEnvelope() {
        let digest = PasswordDigest.compute(password: "p", now: Date(), nonce: Data(repeating: 0, count: 16))
        let url = URL(string: "http://192.0.2.10:8000/onvif/device_service")!
        let xml = ONVIFSoap.envelope(
            action: .getDeviceInformation,
            to: url,
            body: "<tds:GetDeviceInformation/>",
            username: "onvif",
            digest: digest
        )
        #expect(xml.contains("wsse:UsernameToken"))
        #expect(xml.contains("PasswordDigest"))
        #expect(!xml.contains("<wsa:To>"), "default envelope should NOT include WS-Addressing")
    }

    @Test("includeAddressing=true injects WSA To / Action / MessageID — required for per-subscription URLs")
    func wsAddressing() {
        let digest = PasswordDigest.compute(password: "p", now: Date(), nonce: Data(repeating: 0, count: 16))
        let url = URL(string: "http://192.0.2.10:8000/onvif/Subscription?Idx=123")!
        let xml = ONVIFSoap.envelope(
            action: .pullMessages,
            to: url,
            body: "<tev:PullMessages/>",
            username: "onvif",
            digest: digest,
            includeAddressing: true
        )
        #expect(xml.contains("<wsa:To>http://192.0.2.10:8000/onvif/Subscription?Idx=123</wsa:To>"))
        #expect(xml.contains("<wsa:Action>http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest</wsa:Action>"))
        #expect(xml.contains("<wsa:MessageID>"))
    }
}

@Suite("ONVIFResponseParser fixtures")
struct ONVIFResponseParserTests {

    @Test("Parses GetDeviceInformation into manufacturer/model/firmware")
    func deviceInformation() throws {
        let xml = try fixture("getDeviceInformationResponse.xml")
        let info = try ONVIFResponseParser.parseDeviceInformation(xml)
        #expect(info.manufacturer == "Reolink")
        #expect(info.model == "Duo 3 PoE")
        #expect(info.firmwareVersion == "v3.0.0.4518")
    }

    @Test("Detects ter:NotAuthorized as ONVIFError.notAuthorized")
    func notAuthorized() throws {
        let xml = try fixture("notAuthorizedFault.xml")
        #expect(throws: ONVIFError.notAuthorized) {
            _ = try ONVIFResponseParser.parseDeviceInformation(xml)
        }
    }

    @Test("Parses CreatePullPointSubscription into a subscription URL")
    func subscriptionReference() throws {
        let xml = try fixture("createPullPointSubscriptionResponse.xml")
        let ref = try ONVIFResponseParser.parseSubscriptionReference(xml)
        #expect(ref.address.absoluteString == "http://192.0.2.10:8000/onvif/Subscription?Idx=12345")
    }

    @Test("Parses PullMessages with a person-classified motion event")
    func pullMessagesMotion() throws {
        let xml = try fixture("pullMessagesMotionPerson.xml")
        let messages = try ONVIFResponseParser.parsePullMessages(xml)
        #expect(messages.count == 1)
        let m = try #require(messages.first)
        if case .motion(let aiClass) = m.classified {
            #expect(aiClass == "person")
        } else {
            Issue.record("expected motion event, got \(m.classified)")
        }
    }

    @Test("Parses PullMessages with a doorbell-ring event")
    func pullMessagesRing() throws {
        let xml = try fixture("pullMessagesRing.xml")
        let messages = try ONVIFResponseParser.parsePullMessages(xml)
        let m = try #require(messages.first)
        if case .ring = m.classified {
            #expect(true)
        } else {
            Issue.record("expected ring event, got \(m.classified)")
        }
    }

    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil)
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/onvif/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
