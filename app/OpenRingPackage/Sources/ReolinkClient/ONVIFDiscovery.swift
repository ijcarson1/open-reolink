import Foundation
import Network

/// Represents one match from a WS-Discovery `ProbeMatches` response.
public struct DiscoveredCamera: Hashable, Sendable, Identifiable {
    public var id: String { "\(macAddress ?? "")|\(ip)" }
    public let ip: String
    public let macAddress: String?
    public let manufacturer: String
    public let model: String?
    public let onvifEndpoint: URL?

    public init(ip: String, macAddress: String? = nil, manufacturer: String, model: String? = nil, onvifEndpoint: URL? = nil) {
        self.ip = ip
        self.macAddress = macAddress
        self.manufacturer = manufacturer
        self.model = model
        self.onvifEndpoint = onvifEndpoint
    }
}

/// Pluggable discovery surface — swap in a fake in tests.
public protocol ONVIFDiscovering: Sendable {
    func probe(timeout: TimeInterval) async throws -> [DiscoveredCamera]
}

/// Builds the canonical WS-Discovery `Probe` SOAP envelope.
public enum WSDiscovery {
    public static let multicastHost = "239.255.255.250"
    public static let multicastPort: UInt16 = 3702
    public static let manufacturerFilter = "reolink"

    public static func probeXML(messageID: UUID = UUID()) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Envelope xmlns="http://www.w3.org/2003/05/soap-envelope"
                  xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing"
                  xmlns:wsdd="http://schemas.xmlsoap.org/ws/2005/04/discovery"
                  xmlns:tds="http://www.onvif.org/ver10/network/wsdl">
          <Header>
            <wsa:MessageID>urn:uuid:\(messageID.uuidString.lowercased())</wsa:MessageID>
            <wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
            <wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>
          </Header>
          <Body>
            <wsdd:Probe>
              <wsdd:Types>tds:NetworkVideoTransmitter</wsdd:Types>
            </wsdd:Probe>
          </Body>
        </Envelope>
        """
    }

    /// Parses a ProbeMatches SOAP response into a list of `DiscoveredCamera`.
    /// Tolerant of namespace prefix variations.
    public static func parseProbeMatches(_ xml: String) -> [DiscoveredCamera] {
        let parser = ProbeMatchesParser()
        return parser.parse(xml)
    }

    /// Case-insensitive contains-match against the configured manufacturer
    /// filter. Reolink firmware reports "Reolink" (mixed case) on the units
    /// in our fixtures, hence case-insensitive (per Slice 4 quality-pass notes).
    public static func isReolink(_ entry: DiscoveredCamera) -> Bool {
        entry.manufacturer.lowercased().contains(manufacturerFilter)
    }

    /// Dedupes by MAC if present, falling back to IP. Preserves insertion order.
    public static func deduplicate(_ entries: [DiscoveredCamera]) -> [DiscoveredCamera] {
        var seen: Set<String> = []
        var out: [DiscoveredCamera] = []
        for entry in entries {
            let key = entry.macAddress ?? entry.ip
            if seen.insert(key).inserted {
                out.append(entry)
            }
        }
        return out
    }
}

// MARK: - Probe-matches XML parser

private final class ProbeMatchesParser: NSObject, XMLParserDelegate {
    private var entries: [DiscoveredCamera] = []
    private var currentEntry = MutableEntry()
    private var capturing: String?
    private var buffer = ""

    func parse(_ xml: String) -> [DiscoveredCamera] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let local = localName(elementName)
        switch local {
        case "ProbeMatch":
            currentEntry = MutableEntry()
        case "Scopes", "XAddrs", "Address", "Types":
            capturing = local
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing != nil {
            buffer.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = localName(elementName)
        switch local {
        case "Scopes":
            currentEntry.absorbScopes(buffer)
            capturing = nil
        case "XAddrs":
            currentEntry.absorbXAddrs(buffer)
            capturing = nil
        case "Address":
            // wsa:EndpointReference/Address — `urn:uuid:...` form, may embed MAC
            currentEntry.absorbAddress(buffer)
            capturing = nil
        case "Types":
            capturing = nil
        case "ProbeMatch":
            if let entry = currentEntry.build() {
                entries.append(entry)
            }
        default:
            break
        }
    }

    private func localName(_ element: String) -> String {
        if let idx = element.firstIndex(of: ":") {
            return String(element[element.index(after: idx)...])
        }
        return element
    }
}

private struct MutableEntry {
    var ip: String?
    var mac: String?
    var manufacturer: String?
    var model: String?
    var endpoint: URL?

    mutating func absorbScopes(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scope in trimmed.split(separator: " ") {
            guard let url = URL(string: String(scope)) else { continue }
            let host = url.host ?? ""
            let path = url.path.trimmingCharacters(in: .init(charactersIn: "/"))
            if host.contains("onvif") {
                let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
                guard let category = parts.first else { continue }
                let value = parts.count > 1
                    ? String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    : ""
                switch category {
                case "hardware":
                    if model == nil { model = value }
                case "name":
                    if manufacturer == nil { manufacturer = value }
                default:
                    break
                }
            }
        }
    }

    mutating func absorbXAddrs(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for token in trimmed.split(separator: " ") {
            guard let url = URL(string: String(token)) else { continue }
            if endpoint == nil { endpoint = url }
            if let host = url.host, IPv4.isValid(host) { ip = host }
        }
    }

    mutating func absorbAddress(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // ONVIF EndpointReference is of the form `urn:uuid:<uuid>` — many
        // Reolink firmwares embed the MAC as the last 12 hex characters.
        let lower = trimmed.lowercased()
        guard let last = lower.split(separator: ":").last else { return }
        let hex = last.filter { $0.isHexDigit }
        if hex.count >= 12 {
            let macHex = String(hex.suffix(12))
            mac = stride(from: 0, to: macHex.count, by: 2).map {
                let start = macHex.index(macHex.startIndex, offsetBy: $0)
                let end = macHex.index(start, offsetBy: 2)
                return String(macHex[start..<end])
            }.joined(separator: ":")
        }
    }

    func build() -> DiscoveredCamera? {
        guard let ip else { return nil }
        return DiscoveredCamera(
            ip: ip,
            macAddress: mac,
            manufacturer: manufacturer ?? "",
            model: model,
            onvifEndpoint: endpoint
        )
    }
}
