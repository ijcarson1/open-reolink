import Foundation

/// Performs an authenticated SOAP POST to an ONVIF endpoint.
///
/// PasswordDigest is regenerated per request (per the WS-Security spec — a
/// nonce is single-use). HTTP 401 / SOAP fault containing `ter:NotAuthorized`
/// is mapped to `ONVIFError.notAuthorized`; other HTTP non-2xx are mapped to
/// `.http`. Trust handling reuses `SelfSignedTrustDelegate` for the LAN HTTPS
/// case (most Reolink units serve ONVIF over plain HTTP on port 8000 but a
/// minority enable HTTPS).
public final class SoapHTTPClient: @unchecked Sendable {
    private let session: URLSession

    public init(host: String, session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let delegate = SelfSignedTrustDelegate(trustedHost: host)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    public func send(envelope: String, to endpoint: URL, action: ONVIFAction) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8; action=\"\(action.rawValue)\"", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(envelope.utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ONVIFError.transport(String(describing: error))
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        guard let http = response as? HTTPURLResponse else {
            throw ONVIFError.transport("non-HTTP response")
        }
        switch http.statusCode {
        case 200, 202:
            return text
        case 401:
            throw ONVIFError.notAuthorized
        case 400:
            // Reolink's HTTP-400 path on PasswordText — surface that to the caller
            if let fault = ONVIFResponseParser.detectFault(in: text) { throw fault }
            throw ONVIFError.http(400, text)
        default:
            throw ONVIFError.http(http.statusCode, text)
        }
    }
}
