import Foundation
import Testing
@testable import VisionProviders

@Suite("VisionProviders HTTP", .serialized)
struct VisionProvidersHTTPTests {

    init() { VisionStubURLProtocol.reset() }

    // MARK: Anthropic

    @Test("Anthropic: happy path returns the text block from the content array")
    func anthropicHappyPath() async throws {
        let body = try fixture("anthropic_response_ok.json")
        VisionStubURLProtocol.setHandler { _ in (200, body) }
        let provider = AnthropicVisionProvider(apiKey: "x", session: stubSession())
        let result = try await provider.analyze(jpeg: Data([0xFF, 0xD8, 0xFF]), prompt: "Describe this image")
        #expect(result.contains("delivery uniform"))
    }

    @Test("Anthropic: 401 maps to .unauthorized")
    func anthropicUnauthorized() async {
        VisionStubURLProtocol.setHandler { _ in (401, Data("{\"error\":\"invalid key\"}".utf8)) }
        let provider = AnthropicVisionProvider(apiKey: "x", session: stubSession())
        await #expect(throws: VisionProviderError.unauthorized) {
            _ = try await provider.analyze(jpeg: Data(), prompt: "x")
        }
    }

    @Test("Anthropic: 429 maps to .rateLimited")
    func anthropicRateLimited() async {
        VisionStubURLProtocol.setHandler { _ in (429, Data()) }
        let provider = AnthropicVisionProvider(apiKey: "x", session: stubSession())
        await #expect(throws: VisionProviderError.rateLimited) {
            _ = try await provider.analyze(jpeg: Data(), prompt: "x")
        }
    }

    @Test("Anthropic: request body has content-blocks with base64 image + text + correct headers")
    func anthropicRequestShape() async throws {
        let body = try fixture("anthropic_response_ok.json")
        VisionStubURLProtocol.setHandler { _ in (200, body) }
        let provider = AnthropicVisionProvider(apiKey: "test-key", session: stubSession())
        _ = try await provider.analyze(jpeg: Data([0xFF, 0xD8, 0xFF]), prompt: "describe")
        let request = try #require(VisionStubURLProtocol.lastRequest())
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let bodyData = try #require(VisionStubURLProtocol.lastBody())
        let jsonString = String(data: bodyData, encoding: .utf8) ?? ""
        #expect(jsonString.contains("\"type\":\"image\""))
        #expect(jsonString.contains("\"media_type\":\"image\\/jpeg\""))
        #expect(jsonString.contains("\"type\":\"text\""))
    }

    // MARK: OpenAI

    @Test("OpenAI: happy path returns choices[0].message.content")
    func openaiHappyPath() async throws {
        let body = try fixture("openai_response_ok.json")
        VisionStubURLProtocol.setHandler { _ in (200, body) }
        let provider = OpenAIVisionProvider(apiKey: "x", session: stubSession())
        let result = try await provider.analyze(jpeg: Data([0xFF, 0xD8, 0xFF]), prompt: "Describe")
        #expect(result.contains("courier"))
    }

    @Test("OpenAI: request body uses image_url with a data: URL — not content-blocks")
    func openaiRequestShape() async throws {
        let body = try fixture("openai_response_ok.json")
        VisionStubURLProtocol.setHandler { _ in (200, body) }
        let provider = OpenAIVisionProvider(apiKey: "test-key", session: stubSession())
        _ = try await provider.analyze(jpeg: Data([0xFF, 0xD8, 0xFF]), prompt: "x")
        let request = try #require(VisionStubURLProtocol.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let bodyData = try #require(VisionStubURLProtocol.lastBody())
        let jsonString = String(data: bodyData, encoding: .utf8) ?? ""
        #expect(jsonString.contains("\"type\":\"image_url\""))
        #expect(jsonString.contains("data:image\\/jpeg;base64,"))
    }

    @Test("OpenAI: 5xx maps to .serverError")
    func openaiServerError() async {
        VisionStubURLProtocol.setHandler { _ in (503, Data()) }
        let provider = OpenAIVisionProvider(apiKey: "x", session: stubSession())
        await #expect(throws: VisionProviderError.serverError(503)) {
            _ = try await provider.analyze(jpeg: Data(), prompt: "x")
        }
    }
}

@Suite("VisionProviderRegistry")
struct VisionProviderRegistryTests {

    @Test("activeKind=.none returns nil")
    func off() {
        let registry = VisionProviderRegistry(activeKind: .none, anthropicKey: "x", openAIKey: "y")
        #expect(registry.resolve() == nil)
    }

    @Test("Switching active kind preserves the inactive key")
    func switchingPreservesInactive() {
        let onAnthropic = VisionProviderRegistry(activeKind: .anthropic, anthropicKey: "ant", openAIKey: "oai")
        let onOpenAI = VisionProviderRegistry(activeKind: .openai, anthropicKey: "ant", openAIKey: "oai")
        #expect(onAnthropic.resolve()?.displayName == "Anthropic Claude")
        #expect(onOpenAI.resolve()?.displayName == "OpenAI")
        #expect(onAnthropic.anthropicKey == "ant")
        #expect(onAnthropic.openAIKey == "oai")
    }

    @Test("Active provider with empty key returns nil (no degraded call)")
    func emptyKey() {
        let registry = VisionProviderRegistry(activeKind: .anthropic, anthropicKey: "", openAIKey: nil)
        #expect(registry.resolve() == nil)
    }
}

@Suite("RateLimiter token bucket")
struct RateLimiterTests {
    @Test("Allows N consumes per refill window, then blocks until refill")
    func capacity() {
        let nowHolder = TimeHolder(start: Date(timeIntervalSince1970: 1_700_000_000))
        let limiter = RateLimiter(capacity: 1, refillInterval: 60, clock: .init(now: { nowHolder.current() }))
        #expect(limiter.tryConsume(key: "cam-1") == true)
        #expect(limiter.tryConsume(key: "cam-1") == false)
        nowHolder.advance(by: 60)
        #expect(limiter.tryConsume(key: "cam-1") == true)
    }

    @Test("Keys are independent — one camera's quota doesn't affect another")
    func perKey() {
        let limiter = RateLimiter(capacity: 1, refillInterval: 60)
        #expect(limiter.tryConsume(key: "cam-1") == true)
        #expect(limiter.tryConsume(key: "cam-2") == true)
        #expect(limiter.tryConsume(key: "cam-1") == false)
    }

    @Test("Higher capacity = more tokens per window")
    func capacityScales() {
        let limiter = RateLimiter(capacity: 3, refillInterval: 60)
        #expect(limiter.tryConsume(key: "k") == true)
        #expect(limiter.tryConsume(key: "k") == true)
        #expect(limiter.tryConsume(key: "k") == true)
        #expect(limiter.tryConsume(key: "k") == false)
    }
}

// MARK: - test helpers

final class TimeHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(start: Date) { self.date = start }
    func current() -> Date {
        lock.lock(); defer { lock.unlock() }
        return date
    }
    func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        date = date.addingTimeInterval(interval)
    }
}

private func fixture(_ name: String) throws -> Data {
    if let url = Bundle.module.url(forResource: name, withExtension: nil) {
        return try Data(contentsOf: url)
    }
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/vision/\(name)")
    return try Data(contentsOf: url)
}

private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VisionStubURLProtocol.self]
    return URLSession(configuration: config)
}

final class VisionStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _lastRequest: URLRequest?
    nonisolated(unsafe) private static var _lastBody: Data?

    static func setHandler(_ h: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        _handler = h
    }
    static func lastRequest() -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }
    static func lastBody() -> Data? {
        lock.lock(); defer { lock.unlock() }
        return _lastBody
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _lastRequest = nil
        _lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._lastRequest = request
        // URLProtocol drops the body unless we re-read via httpBodyStream
        if let stream = request.httpBodyStream {
            var data = Data()
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            Self._lastBody = data
        } else if let body = request.httpBody {
            Self._lastBody = body
        }
        let handler = Self._handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
