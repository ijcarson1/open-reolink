import Foundation
import Network

/// Real `Network.framework`-backed WS-Discovery probe over UDP multicast.
///
/// Sends a single Probe to 239.255.255.250:3702 and listens for ProbeMatches
/// for the duration of the timeout window. Reolink-filtered, deduplicated.
///
/// Requires the `com.apple.security.network.multicast` entitlement
/// (added in `app/Config/OpenRing.entitlements` for this slice).
public final class NetworkONVIFDiscovery: ONVIFDiscovering, @unchecked Sendable {
    public init() {}

    public func probe(timeout: TimeInterval) async throws -> [DiscoveredCamera] {
        let messageID = UUID()
        let payload = Data(WSDiscovery.probeXML(messageID: messageID).utf8)

        let endpoint = NWEndpoint.hostPort(
            host: .init(WSDiscovery.multicastHost),
            port: .init(rawValue: WSDiscovery.multicastPort)!
        )
        let group = try NWMulticastGroup(for: [endpoint])
        let queue = DispatchQueue(label: "onvif.discovery")
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let collector = ResponseCollector()
        let connectionGroup = NWConnectionGroup(with: group, using: parameters)
        connectionGroup.setReceiveHandler(maximumMessageSize: 32_768, rejectOversizedMessages: true) { _, content, _ in
            guard let content, let text = String(data: content, encoding: .utf8) else { return }
            let matches = WSDiscovery.parseProbeMatches(text)
                .filter(WSDiscovery.isReolink)
            collector.append(matches)
        }

        connectionGroup.start(queue: queue)
        connectionGroup.send(content: payload, completion: { _ in })

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

        connectionGroup.cancel()
        return WSDiscovery.deduplicate(collector.snapshot())
    }
}

private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [DiscoveredCamera] = []

    func append(_ new: [DiscoveredCamera]) {
        lock.lock(); defer { lock.unlock() }
        entries.append(contentsOf: new)
    }

    func snapshot() -> [DiscoveredCamera] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}
