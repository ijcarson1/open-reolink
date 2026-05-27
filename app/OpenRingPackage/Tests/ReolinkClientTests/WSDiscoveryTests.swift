import Foundation
import Testing
@testable import ReolinkClient

@Suite("WS-Discovery probe + parser")
struct WSDiscoveryTests {

    @Test("Probe XML carries required namespaces and a fresh UUID")
    func probeShape() {
        let uuid = UUID()
        let xml = WSDiscovery.probeXML(messageID: uuid)
        #expect(xml.contains("xmlns:wsdd=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\""))
        #expect(xml.contains("xmlns:tds=\"http://www.onvif.org/ver10/network/wsdl\""))
        #expect(xml.contains("xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\""))
        #expect(xml.contains("urn:uuid:\(uuid.uuidString.lowercased())"))
        #expect(xml.contains("tds:NetworkVideoTransmitter"))
    }

    @Test("Probe XML uses a fresh UUID on every call")
    func probeUuidFresh() {
        let a = WSDiscovery.probeXML()
        let b = WSDiscovery.probeXML()
        #expect(a != b)
    }

    @Test("Parses real ProbeMatches XML into DiscoveredCameras")
    func parseFixture() throws {
        let xml = try fixture("probematches_reolink.xml")
        let entries = WSDiscovery.parseProbeMatches(xml)
        #expect(entries.count == 2)
        let ips = entries.map(\.ip)
        #expect(ips.contains("192.0.2.10"))
        #expect(ips.contains("192.0.2.11"))
        let duo = try #require(entries.first { $0.ip == "192.0.2.10" })
        #expect(duo.manufacturer == "Reolink")
        #expect(duo.model == "Duo 3 PoE")
        #expect(duo.onvifEndpoint?.absoluteString == "http://192.0.2.10:8000/onvif/device_service")
    }

    @Test("Reolink filter is case-insensitive")
    func filterCaseInsensitive() {
        let lower = DiscoveredCamera(ip: "192.0.2.10", manufacturer: "reolink")
        let mixed = DiscoveredCamera(ip: "192.0.2.11", manufacturer: "Reolink")
        let upper = DiscoveredCamera(ip: "192.0.2.12", manufacturer: "REOLINK")
        let axis = DiscoveredCamera(ip: "192.0.2.50", manufacturer: "Axis Communications")
        #expect(WSDiscovery.isReolink(lower))
        #expect(WSDiscovery.isReolink(mixed))
        #expect(WSDiscovery.isReolink(upper))
        #expect(!WSDiscovery.isReolink(axis))
    }

    @Test("Non-Reolink fixture filters down to zero matches")
    func nonReolinkFiltered() throws {
        let xml = try fixture("probematches_nonreolink.xml")
        let entries = WSDiscovery.parseProbeMatches(xml).filter(WSDiscovery.isReolink)
        #expect(entries.isEmpty)
    }

    @Test("Deduplication prefers MAC; falls back to IP when MAC is missing")
    func dedup() {
        let a = DiscoveredCamera(ip: "192.0.2.10", macAddress: "aa:bb:cc:dd:ee:ff", manufacturer: "Reolink")
        let aDuplicate = DiscoveredCamera(ip: "192.0.2.10", macAddress: "aa:bb:cc:dd:ee:ff", manufacturer: "Reolink")
        let b = DiscoveredCamera(ip: "192.0.2.11", macAddress: nil, manufacturer: "Reolink")
        let bIPDup = DiscoveredCamera(ip: "192.0.2.11", macAddress: nil, manufacturer: "Reolink")
        let unique = WSDiscovery.deduplicate([a, aDuplicate, b, bIPDup])
        #expect(unique.count == 2)
        #expect(unique[0].ip == "192.0.2.10")
        #expect(unique[1].ip == "192.0.2.11")
    }

    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil)
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/onvif/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
