import Foundation
import Testing
@testable import ReolinkClient

@Suite("StreamReconnectScheduler")
struct StreamReconnectSchedulerTests {

    @Test("Produces 1s → 2s → 4s → 8s then stays at 8s thereafter")
    func sequence() {
        let scheduler = StreamReconnectScheduler()
        #expect(scheduler.nextDelay() == 1)
        #expect(scheduler.nextDelay() == 2)
        #expect(scheduler.nextDelay() == 4)
        #expect(scheduler.nextDelay() == 8)
        #expect(scheduler.nextDelay() == 8)
        #expect(scheduler.nextDelay() == 8)
    }

    @Test("Reset returns to the first delay")
    func reset() {
        let scheduler = StreamReconnectScheduler()
        _ = scheduler.nextDelay()
        _ = scheduler.nextDelay()
        scheduler.reset()
        #expect(scheduler.nextDelay() == 1)
    }

    @Test("RTSP URL is built from Camera fields with main / sub paths")
    func rtspURL() throws {
        let camera = Camera(displayName: "Cam", lanIP: "192.0.2.30", rtspPort: 554, adminUsername: "admin")
        let main = try #require(reolinkRTSPURL(for: camera, password: "p w", quality: .main))
        let sub = try #require(reolinkRTSPURL(for: camera, password: "p w", quality: .sub))
        #expect(main.absoluteString.contains("rtsp://"))
        #expect(main.absoluteString.contains("@192.0.2.30:554"))
        #expect(main.absoluteString.hasSuffix("/h264Preview_01_main"))
        #expect(sub.absoluteString.hasSuffix("/h264Preview_01_sub"))
    }
}
