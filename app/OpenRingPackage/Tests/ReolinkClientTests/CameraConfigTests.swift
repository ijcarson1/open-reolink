import Foundation
import Testing
@testable import ReolinkClient

@Suite("CameraConfig")
struct CameraConfigTests {

    @Test("Loads from environment with all defaults")
    func loadsFromEnvWithDefaults() throws {
        let cfg = try #require(CameraConfig.load(environment: [
            "REOLINK_IP": "192.0.2.10",
            "REOLINK_PASSWORD": "secret",
        ]))
        #expect(cfg.camera.lanIP == "192.0.2.10")
        #expect(cfg.camera.adminUsername == "admin")
        #expect(cfg.camera.cgiScheme == "https")
        #expect(cfg.camera.cgiPort == 443)
        #expect(cfg.camera.kind == .camera)
        #expect(cfg.password == "secret")
    }

    @Test("Honours overrides for scheme, port, user, kind, and name")
    func loadsWithOverrides() throws {
        let cfg = try #require(CameraConfig.load(environment: [
            "REOLINK_IP": "192.0.2.20",
            "REOLINK_PASSWORD": "secret",
            "REOLINK_USER": "alice",
            "REOLINK_SCHEME": "http",
            "REOLINK_PORT": "8080",
            "REOLINK_KIND": "doorbell",
            "REOLINK_NAME": "Front door",
        ]))
        #expect(cfg.camera.cgiScheme == "http")
        #expect(cfg.camera.cgiPort == 8080)
        #expect(cfg.camera.adminUsername == "alice")
        #expect(cfg.camera.kind == .doorbell)
        #expect(cfg.camera.displayName == "Front door")
    }

    @Test("Returns nil when required keys are missing")
    func missingKeys() {
        #expect(CameraConfig.load(environment: [:]) == nil)
        #expect(CameraConfig.load(environment: ["REOLINK_IP": "192.0.2.10"]) == nil)
        #expect(CameraConfig.load(environment: ["REOLINK_PASSWORD": "x"]) == nil)
    }

    @Test("Parses a .env file with comments and quoted values")
    func parsesDotEnv() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("open-reolink-\(UUID()).env")
        let contents = """
        # comment line
        REOLINK_IP=10.0.0.5
        REOLINK_PASSWORD="qu o ted"
        REOLINK_USER=  admin

        REOLINK_NAME='Camera One'
        """
        try contents.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = CameraConfig.parseDotEnv(at: tmp.path)
        #expect(parsed["REOLINK_IP"] == "10.0.0.5")
        #expect(parsed["REOLINK_PASSWORD"] == "qu o ted")
        #expect(parsed["REOLINK_USER"] == "admin")
        #expect(parsed["REOLINK_NAME"] == "Camera One")
        #expect(parsed["# comment line"] == nil)
    }
}
