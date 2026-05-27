import Foundation
import Testing
@testable import ReolinkClient

@Suite("ReolinkCGIClient", .serialized)
struct ReolinkCGIClientTests {

    init() {
        StubURLProtocol.reset()
    }

    @Test("Returns JPEG bytes on HTTP 200 with valid magic")
    func returnsJPEG() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + Data(repeating: 0, count: 256)
        StubURLProtocol.setHandler { _ in (200, jpeg) }
        let client = makeClient()
        let result = try await client.fetchSnapshot()
        #expect(result.first == 0xFF)
        #expect(result.count == jpeg.count)
    }

    @Test("Maps HTTP 401 to .unauthorized")
    func unauthorized() async throws {
        StubURLProtocol.setHandler { _ in (401, Data()) }
        let client = makeClient()
        await #expect(throws: CameraClientError.unauthorized) {
            _ = try await client.fetchSnapshot()
        }
    }

    @Test("Maps HTTP 423 to .lockedOut")
    func lockedOut() async throws {
        StubURLProtocol.setHandler { _ in (423, Data()) }
        let client = makeClient()
        await #expect(throws: CameraClientError.lockedOut) {
            _ = try await client.fetchSnapshot()
        }
    }

    @Test("Rejects non-JPEG 200 response")
    func rejectsBadPayload() async throws {
        StubURLProtocol.setHandler { _ in (200, Data([0x00, 0x01, 0x02])) }
        let client = makeClient()
        await #expect(throws: CameraClientError.self) {
            _ = try await client.fetchSnapshot()
        }
    }

    @Test("Request targets the configured camera and CGI path")
    func buildsRequestURL() async throws {
        StubURLProtocol.setHandler { _ in
            (200, Data([0xFF, 0xD8, 0xFF]) + Data(repeating: 0, count: 16))
        }
        let client = makeClient()
        _ = try await client.fetchSnapshot()
        let url = try #require(StubURLProtocol.lastRequest()?.url)
        #expect(url.scheme == "https")
        #expect(url.host == "192.0.2.10")
        #expect(url.path == "/cgi-bin/api.cgi")
        let query = url.query ?? ""
        #expect(query.contains("cmd=Snap"))
        #expect(query.contains("channel=0"))
        #expect(query.contains("user=admin"))
    }

    private func makeClient() -> ReolinkCGIClient {
        let camera = Camera(
            displayName: "Test",
            lanIP: "192.0.2.10",
            kind: .camera,
            cgiScheme: "https",
            cgiPort: 443,
            adminUsername: "admin"
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return ReolinkCGIClient(camera: camera, password: "pw", session: session)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _lastRequest: URLRequest?

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    static func lastRequest() -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._lastRequest = request
        let handler = Self._handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
