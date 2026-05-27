import Foundation
import Testing
@testable import ReolinkClient

@Suite("IPv4 validator")
struct IPv4ValidationTests {

    @Test("Accepts canonical dotted-quad IPv4")
    func valid() {
        for ip in ["192.168.1.20", "10.0.0.1", "0.0.0.0", "255.255.255.255"] {
            #expect(IPv4.isValid(ip), "expected valid: \(ip)")
        }
    }

    @Test("Rejects hostnames")
    func rejectsHostnames() {
        for host in ["camera.local", "google.com", "frontdoor"] {
            #expect(!IPv4.isValid(host), "expected invalid: \(host)")
        }
    }

    @Test("Rejects IPv6")
    func rejectsIPv6() {
        for ip in ["::1", "fe80::1", "2001:db8::1", "::ffff:192.0.2.1"] {
            #expect(!IPv4.isValid(ip), "expected invalid: \(ip)")
        }
    }

    @Test("Rejects malformed input")
    func rejectsMalformed() {
        for input in ["", "192.168.1", "192.168.1.1.1", "192.168.1.256", "192.168.-1.1", "abc.def.ghi.jkl", "192.168.1.20 "] {
            #expect(!IPv4.isValid(input), "expected invalid: \(input)")
        }
    }

    @Test("Rejects leading zeros (octal-interpretation guard)")
    func rejectsLeadingZeros() {
        for input in ["010.0.0.1", "192.168.01.1", "00.0.0.0"] {
            #expect(!IPv4.isValid(input), "expected invalid: \(input)")
        }
    }
}
