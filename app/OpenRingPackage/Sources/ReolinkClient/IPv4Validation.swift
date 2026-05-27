import Foundation

/// IPv4 validator per `CONTEXT.md`: a Camera is identified by IP, not hostname.
///
/// Accepts dotted-quad IPv4 in canonical form. Rejects hostnames, IPv6, and
/// malformed input. Leading zeros are rejected to avoid octal-interpretation
/// ambiguity (e.g. `010.0.0.1` is octal 8 on some resolvers).
public enum IPv4 {
    public static func isValid(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard !part.isEmpty, part.count <= 3 else { return false }
            // Reject leading zero (except literal "0")
            if part.count > 1 && part.first == "0" { return false }
            guard let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }
}
