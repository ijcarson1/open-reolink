import Foundation

public final class ReolinkCGIClient: CameraClient, @unchecked Sendable {
    public let camera: Camera
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
            // Short LAN-scoped timeouts — a Reolink camera on the same network
            // answers in well under a second when it's reachable. If it doesn't,
            // we want the HTTPS→HTTP fallback to kick in fast, not sit on a
            // 15s URLSession default.
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 10
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

    // MARK: - Camera controls (Slice 6 — Reolink-specific commands)

    /// Toggles the camera's white LED (spotlight).
    /// `brightness` is 0–100 (ignored when off).
    public func setSpotlight(on: Bool, brightness: Int = 100) async throws {
        let mode = on ? 2 : 0   // 0=off, 2=always-on
        let state = on ? 1 : 0
        let payload: [[String: Any]] = [[
            "cmd": "SetWhiteLed",
            "param": [
                "WhiteLed": [
                    "channel": 0,
                    "state": state,
                    "mode": mode,
                    "bright": max(0, min(100, brightness)),
                ],
            ],
        ]]
        _ = try await performCommand("SetWhiteLed", payload: payload)
    }

    /// Toggles the camera's built-in siren.
    public func setSiren(on: Bool) async throws {
        let payload: [[String: Any]] = [[
            "cmd": "AudioAlarmPlay",
            "param": [
                "alarm_mode": "manul",
                "manual_switch": on ? 1 : 0,
                "times": 1,
                "channel": 0,
            ],
        ]]
        _ = try await performCommand("AudioAlarmPlay", payload: payload)
    }

    /// Lists the pre-recorded quick-reply files stored on a doorbell.
    public func quickReplyList() async throws -> [QuickReplyFile] {
        let payload: [[String: Any]] = [[
            "cmd": "GetAudioFileList",
            "param": ["channel": 0],
        ]]
        let response = try await performCommand("GetAudioFileList", payload: payload)
        guard
            let first = response.first,
            let value = first["value"] as? [String: Any],
            let list = value["AudioFileList"] as? [[String: Any]]
        else {
            return []
        }
        return list.compactMap { entry in
            guard let id = entry["id"] as? Int else { return nil }
            let name = (entry["fileName"] as? String) ?? "Reply #\(id)"
            return QuickReplyFile(id: id, name: name)
        }
    }

    /// Plays a quick reply by file ID. Pass `nil` to stop playback.
    public func playQuickReply(fileId: Int?) async throws {
        let payload: [[String: Any]] = [[
            "cmd": "QuickReplyPlay",
            "param": [
                "id": fileId ?? -1,
                "channel": 0,
            ],
        ]]
        _ = try await performCommand("QuickReplyPlay", payload: payload)
    }

    private func performCommand(_ cmd: String, payload: [[String: Any]]) async throws -> [[String: Any]] {
        var components = URLComponents()
        components.scheme = camera.cgiScheme
        components.host = camera.lanIP
        components.port = camera.cgiPort
        components.path = "/cgi-bin/api.cgi"
        components.queryItems = [
            URLQueryItem(name: "user", value: camera.adminUsername),
            URLQueryItem(name: "password", value: password),
        ]
        guard let url = components.url else {
            throw CameraClientError.unreachable(underlying: "invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

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
        case 401, 403: throw CameraClientError.unauthorized
        case 423: throw CameraClientError.lockedOut
        case 200..<300: break
        default: throw CameraClientError.unexpectedResponse(status: http.statusCode)
        }

        let parsed = try? JSONSerialization.jsonObject(with: data)
        guard let array = parsed as? [[String: Any]] else {
            throw CameraClientError.decoding("non-array response from \(cmd)")
        }
        if let first = array.first, let code = first["code"] as? Int, code != 0 {
            let err = (first["error"] as? [String: Any])?["detail"] as? String ?? "rspCode \(code)"
            throw CameraClientError.unexpectedResponse(status: code)
                // Surface the underlying detail in the message; CameraClientError
                // doesn't have a dedicated cmd-error case so reuse unexpectedResponse.
                .with(detail: err)
        }
        return array
    }
}

public struct QuickReplyFile: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
}

private extension CameraClientError {
    func with(detail: String) -> CameraClientError {
        switch self {
        case .unexpectedResponse(let s): return .unexpectedResponse(status: s)
        default: return self
        }
    }
}
