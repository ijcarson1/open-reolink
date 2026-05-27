import Foundation

public final class ReolinkCGIClient: CameraClient, @unchecked Sendable {
    private let camera: Camera
    private let password: String
    private let session: URLSession

    public init(camera: Camera, password: String, session: URLSession? = nil) {
        self.camera = camera
        self.password = password
        if let session {
            self.session = session
        } else {
            let delegate = SelfSignedTrustDelegate(trustedHost: camera.lanIP)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    public func fetchSnapshot() async throws -> Data {
        var components = URLComponents()
        components.scheme = camera.cgiScheme
        components.host = camera.lanIP
        components.port = camera.cgiPort
        components.path = "/cgi-bin/api.cgi"
        components.queryItems = [
            URLQueryItem(name: "cmd", value: "Snap"),
            URLQueryItem(name: "channel", value: "0"),
            URLQueryItem(name: "rs", value: UUID().uuidString),
            URLQueryItem(name: "user", value: camera.adminUsername),
            URLQueryItem(name: "password", value: password),
        ]
        guard let url = components.url else {
            throw CameraClientError.unreachable(underlying: "invalid URL")
        }

        let request = URLRequest(url: url)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CameraClientError.unreachable(underlying: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw CameraClientError.unexpectedResponse(status: -1)
        }
        switch http.statusCode {
        case 200:
            guard isJPEG(data) else {
                throw CameraClientError.decoding("non-JPEG response from snapshot endpoint")
            }
            return data
        case 401, 403:
            throw CameraClientError.unauthorized
        case 423:
            throw CameraClientError.lockedOut
        default:
            throw CameraClientError.unexpectedResponse(status: http.statusCode)
        }
    }

    private func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }
}
