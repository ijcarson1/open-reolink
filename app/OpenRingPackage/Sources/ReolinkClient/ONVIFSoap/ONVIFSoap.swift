import Foundation

public enum ONVIFAction: String, Sendable {
    case getDeviceInformation = "http://www.onvif.org/ver10/device/wsdl/GetDeviceInformation"
    case getCapabilities = "http://www.onvif.org/ver10/device/wsdl/GetCapabilities"
    case createPullPointSubscription = "http://www.onvif.org/ver10/events/wsdl/EventPortType/CreatePullPointSubscriptionRequest"
    case pullMessages = "http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest"
    case renew = "http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/RenewRequest"
    case unsubscribe = "http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/UnsubscribeRequest"
}

public enum ONVIFError: Error, Sendable, Equatable {
    case notAuthorized
    case malformed(String)
    case transport(String)
    case http(Int, String)
}

/// Pure SOAP envelope builder + WS-Security/WS-Addressing header injection.
///
/// Reolink-firmware quirks honoured here (per ADR-0004):
///   - PasswordDigest auth only (PasswordText returns HTTP 400)
///   - WS-Addressing headers required on per-subscription endpoints
public enum ONVIFSoap {

    public static func envelope(
        action: ONVIFAction,
        to endpoint: URL,
        body: String,
        username: String? = nil,
        digest: PasswordDigest? = nil,
        messageID: UUID = UUID(),
        includeAddressing: Bool = false
    ) -> String {
        let header: String
        if includeAddressing {
            header = """
                <s:Header>
                  \(securityHeader(username: username, digest: digest))
                  <wsa:MessageID>urn:uuid:\(messageID.uuidString.lowercased())</wsa:MessageID>
                  <wsa:To>\(escape(endpoint.absoluteString))</wsa:To>
                  <wsa:Action>\(action.rawValue)</wsa:Action>
                </s:Header>
                """
        } else if let username, let digest {
            header = """
                <s:Header>
                  \(securityHeader(username: username, digest: digest))
                </s:Header>
                """
        } else {
            header = "<s:Header/>"
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                        xmlns:wsa="http://www.w3.org/2005/08/addressing"
                        xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                        xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
                        xmlns:tds="http://www.onvif.org/ver10/device/wsdl"
                        xmlns:tev="http://www.onvif.org/ver10/events/wsdl"
                        xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2"
                        xmlns:tt="http://www.onvif.org/ver10/schema">
              \(header)
              <s:Body>
                \(body)
              </s:Body>
            </s:Envelope>
            """
    }

    private static func securityHeader(username: String?, digest: PasswordDigest?) -> String {
        guard let username, let digest else { return "" }
        return """
            <wsse:Security s:mustUnderstand="1">
              <wsse:UsernameToken>
                <wsse:Username>\(escape(username))</wsse:Username>
                <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">\(digest.digest)</wsse:Password>
                <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">\(digest.nonceBase64)</wsse:Nonce>
                <wsu:Created>\(digest.createdAt)</wsu:Created>
              </wsse:UsernameToken>
            </wsse:Security>
            """
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
