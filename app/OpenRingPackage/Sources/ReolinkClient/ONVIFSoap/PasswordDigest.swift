import Foundation
import CommonCrypto

/// WS-Security UsernameToken `PasswordDigest` per the ONVIF / OASIS spec.
///
/// Reolink firmware rejects `PasswordText` with HTTP 400 ("malformed request")
/// per ADR-0004; only `PasswordDigest` is accepted. The digest is the base64
/// of SHA1(nonce + created + password), where:
///   - nonce: raw bytes (sent in the envelope as base64)
///   - created: ISO-8601 timestamp without fractional seconds (UTC)
///   - password: the plaintext password
public struct PasswordDigest: Sendable, Equatable {
    public let nonce: Data
    public let createdAt: String
    public let digest: String

    /// Produces a fresh PasswordDigest given the plaintext password.
    /// `now` and `nonce` are injectable for deterministic tests.
    public static func compute(
        password: String,
        now: Date = Date(),
        nonce: Data = randomNonce()
    ) -> PasswordDigest {
        let created = isoFormatter.string(from: now)
        let createdBytes = Data(created.utf8)
        let passwordBytes = Data(password.utf8)
        var combined = Data()
        combined.append(nonce)
        combined.append(createdBytes)
        combined.append(passwordBytes)
        let digestData = sha1(combined)
        return PasswordDigest(
            nonce: nonce,
            createdAt: created,
            digest: digestData.base64EncodedString()
        )
    }

    public var nonceBase64: String { nonce.base64EncodedString() }

    public static func randomNonce(length: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes)
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }
    private static var isoFormatter: ISO8601DateFormatter { makeFormatter() }

    private static func sha1(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA1(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
