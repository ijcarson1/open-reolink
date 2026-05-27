import Foundation

/// Developer-local single-camera config for Slice 1.
///
/// Storage of multiple Cameras (GRDB + Keychain) lands in Slice 2; this loader
/// is the temporary path that gets us off hardcoded values without persistence.
///
/// Loads from environment variables, falling back to a gitignored `.env` file
/// at the repository root or under `~/.config/open-reolink/.env`.
///
/// Required keys:
///   REOLINK_IP
///   REOLINK_USER          (defaults to "admin")
///   REOLINK_PASSWORD
///   REOLINK_NAME          (optional display name; defaults to IP)
///   REOLINK_KIND          (optional; "camera" or "doorbell", default "camera")
///   REOLINK_SCHEME        (optional; "http" or "https", default "https")
///   REOLINK_PORT          (optional; default 443 for https, 80 for http)
public struct CameraConfig: Sendable {
    public let camera: Camera
    public let password: String

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> CameraConfig? {
        var env = environment
        for path in dotEnvSearchPaths() {
            if FileManager.default.fileExists(atPath: path) {
                for (k, v) in parseDotEnv(at: path) where env[k] == nil {
                    env[k] = v
                }
            }
        }
        guard let ip = env["REOLINK_IP"], !ip.isEmpty,
              let password = env["REOLINK_PASSWORD"], !password.isEmpty
        else { return nil }

        let scheme = env["REOLINK_SCHEME"] ?? "https"
        let port = env["REOLINK_PORT"].flatMap { Int($0) } ?? (scheme == "http" ? 80 : 443)
        let kind: CameraKind = env["REOLINK_KIND"] == "doorbell" ? .doorbell : .camera
        let camera = Camera(
            displayName: env["REOLINK_NAME"] ?? ip,
            lanIP: ip,
            kind: kind,
            cgiScheme: scheme,
            cgiPort: port,
            adminUsername: env["REOLINK_USER"] ?? "admin"
        )
        return CameraConfig(camera: camera, password: password)
    }

    private static func dotEnvSearchPaths() -> [String] {
        var paths: [String] = []
        if let cwd = ProcessInfo.processInfo.environment["PWD"] {
            paths.append("\(cwd)/.env")
        }
        let home = NSHomeDirectory()
        paths.append("\(home)/.config/open-reolink/.env")
        return paths
    }

    static func parseDotEnv(at path: String) -> [String: String] {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let eq = trimmed.firstIndex(of: "=")
            else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }
}
