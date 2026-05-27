import Foundation

public struct ONVIFDeviceInformation: Sendable, Equatable {
    public var manufacturer: String
    public var model: String
    public var firmwareVersion: String
    public var serialNumber: String?
    public var hardwareId: String?

    public init(manufacturer: String, model: String, firmwareVersion: String, serialNumber: String? = nil, hardwareId: String? = nil) {
        self.manufacturer = manufacturer
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.serialNumber = serialNumber
        self.hardwareId = hardwareId
    }
}

public struct ONVIFSubscriptionReference: Sendable, Equatable {
    public var address: URL
    public init(address: URL) { self.address = address }
}

public enum ONVIFEventTopic: Sendable, Equatable {
    case motion(aiClass: String?)
    case ring
    case other(String)
}

public struct ONVIFPullMessage: Sendable, Equatable {
    public var topic: String
    public var classified: ONVIFEventTopic
    public var occurredAt: Date

    public init(topic: String, classified: ONVIFEventTopic, occurredAt: Date) {
        self.topic = topic
        self.classified = classified
        self.occurredAt = occurredAt
    }
}

public struct ONVIFCapabilities: Sendable, Equatable {
    public var eventsXAddr: URL?
    public init(eventsXAddr: URL? = nil) { self.eventsXAddr = eventsXAddr }
}

public enum ONVIFResponseParser {

    /// Returns `.notAuthorized` when the SOAP fault is `ter:NotAuthorized`,
    /// `.malformed(...)` for any other SOAP fault, `nil` when no fault.
    public static func detectFault(in xml: String) -> ONVIFError? {
        if xml.contains("ter:NotAuthorized") || xml.contains("NotAuthorized") {
            return .notAuthorized
        }
        if xml.contains("<s:Fault") || xml.contains("<SOAP-ENV:Fault") || xml.contains("<env:Fault") {
            return .malformed("SOAP fault: \(extractFaultReason(xml) ?? "unspecified")")
        }
        return nil
    }

    public static func parseDeviceInformation(_ xml: String) throws -> ONVIFDeviceInformation {
        if let fault = detectFault(in: xml) { throw fault }
        let manufacturer = extractText(xml, "Manufacturer") ?? ""
        let model = extractText(xml, "Model") ?? ""
        let firmware = extractText(xml, "FirmwareVersion") ?? ""
        if manufacturer.isEmpty && model.isEmpty && firmware.isEmpty {
            throw ONVIFError.malformed("GetDeviceInformation response missing all expected fields")
        }
        return ONVIFDeviceInformation(
            manufacturer: manufacturer,
            model: model,
            firmwareVersion: firmware,
            serialNumber: extractText(xml, "SerialNumber"),
            hardwareId: extractText(xml, "HardwareId")
        )
    }

    public static func parseCapabilities(_ xml: String) throws -> ONVIFCapabilities {
        if let fault = detectFault(in: xml) { throw fault }
        let eventsXAddr = extractText(xml, "XAddr").flatMap { URL(string: $0) }
        return ONVIFCapabilities(eventsXAddr: eventsXAddr)
    }

    public static func parseSubscriptionReference(_ xml: String) throws -> ONVIFSubscriptionReference {
        if let fault = detectFault(in: xml) { throw fault }
        guard
            let address = extractText(xml, "Address"),
            let url = URL(string: address)
        else {
            throw ONVIFError.malformed("CreatePullPointSubscription missing Address")
        }
        return ONVIFSubscriptionReference(address: url)
    }

    public static func parsePullMessages(_ xml: String) throws -> [ONVIFPullMessage] {
        if let fault = detectFault(in: xml) { throw fault }
        let parser = PullMessagesXMLParser()
        return parser.parse(xml)
    }

    public static func classify(topic: String, dataXML: String? = nil) -> ONVIFEventTopic {
        let lower = topic.lowercased()
        if lower.contains("visitor") || lower.contains("digitalinput") || lower.contains("button") || lower.contains("doorbell") {
            return .ring
        }
        if lower.contains("motion") || lower.contains("ruleengine") || lower.contains("celldetector") {
            let aiClass = inferAIClass(from: topic, data: dataXML)
            return .motion(aiClass: aiClass)
        }
        return .other(topic)
    }

    // MARK: - helpers

    private static func extractText(_ xml: String, _ localName: String) -> String? {
        // Match either <prefix:LocalName>...</prefix:LocalName> or <LocalName>...</LocalName>
        let patterns = [
            #"<([\w-]+:)?\#(localName)>\s*([^<]+)\s*</[^>]+>"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(xml.startIndex..., in: xml)
            if let match = regex.firstMatch(in: xml, range: range),
               match.numberOfRanges >= 3,
               let bodyRange = Range(match.range(at: 2), in: xml) {
                return String(xml[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func extractFaultReason(_ xml: String) -> String? {
        if let text = extractText(xml, "Text") { return text }
        if let value = extractText(xml, "Value") { return value }
        return nil
    }

    private static func inferAIClass(from topic: String, data: String?) -> String? {
        let lower = (topic + " " + (data ?? "")).lowercased()
        for klass in ["person", "vehicle", "animal", "dog", "package"] {
            if lower.contains(klass) {
                return klass
            }
        }
        return nil
    }
}

private final class PullMessagesXMLParser: NSObject, XMLParserDelegate {
    private var messages: [ONVIFPullMessage] = []
    private var currentTopic: String?
    private var currentTime: Date?
    private var currentDataXML: String?
    private var buffer = ""
    private var capturing: String?
    private var inMessage = false
    private var dataDepth = 0

    func parse(_ xml: String) -> [ONVIFPullMessage] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return messages
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let local = localName(elementName)
        switch local {
        case "NotificationMessage":
            inMessage = true
            currentTopic = nil
            currentTime = nil
            currentDataXML = ""
        case "Topic":
            capturing = "Topic"
            buffer = ""
        case "Message":
            // The <Message UtcTime="..."> attribute carries the timestamp
            if let utc = attributes["UtcTime"] ?? attributes["utcTime"] {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                currentTime = f.date(from: utc) ?? {
                    let f2 = ISO8601DateFormatter()
                    f2.formatOptions = [.withInternetDateTime]
                    return f2.date(from: utc)
                }()
            }
        case "Data":
            dataDepth += 1
            capturing = "Data"
            buffer = ""
        case "SimpleItem":
            // SimpleItem Name="X" Value="Y" — capture into Data context as text
            if dataDepth > 0,
               let name = attributes["Name"], let value = attributes["Value"] {
                currentDataXML?.append("\(name)=\(value);")
            }
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
        case "Topic":
            currentTopic = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            capturing = nil
        case "Data":
            dataDepth -= 1
            if dataDepth == 0 {
                currentDataXML?.append(buffer)
                capturing = nil
            }
        case "NotificationMessage":
            inMessage = false
            guard let topic = currentTopic else { return }
            let classified = ONVIFResponseParser.classify(topic: topic, dataXML: currentDataXML)
            messages.append(ONVIFPullMessage(
                topic: topic,
                classified: classified,
                occurredAt: currentTime ?? Date()
            ))
            currentTopic = nil
            currentTime = nil
            currentDataXML = nil
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
