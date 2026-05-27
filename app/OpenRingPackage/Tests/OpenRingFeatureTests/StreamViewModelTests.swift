import Foundation
import Combine
import Testing
import ReolinkClient
@testable import OpenRingFeature

@Suite("StreamViewModel grid / hero lifecycle")
@MainActor
struct StreamViewModelTests {

    @Test("startGrid attaches a sub-quality session per camera")
    func startGrid() async {
        let cameras = [
            Camera(displayName: "A", lanIP: "192.0.2.10"),
            Camera(displayName: "B", lanIP: "192.0.2.11"),
        ]
        let lifecycle = LifecycleLog()
        let viewModel = StreamViewModel { camera, quality in
            FakeStreamSession(camera: camera, quality: quality, log: lifecycle)
        }
        viewModel.startGrid(cameras: cameras)

        #expect(viewModel.activeSessionCount() == 2)
        #expect(viewModel.quality(for: cameras[0].id) == .sub)
        #expect(viewModel.quality(for: cameras[1].id) == .sub)
    }

    @Test("enterHero swaps that camera's session to main quality, keeps others at sub")
    func enterHero() async {
        let cameras = [
            Camera(displayName: "A", lanIP: "192.0.2.10"),
            Camera(displayName: "B", lanIP: "192.0.2.11"),
        ]
        let log = LifecycleLog()
        let viewModel = StreamViewModel { camera, quality in
            FakeStreamSession(camera: camera, quality: quality, log: log)
        }
        viewModel.startGrid(cameras: cameras)
        viewModel.enterHero(camera: cameras[0])

        #expect(viewModel.quality(for: cameras[0].id) == .main)
        #expect(viewModel.quality(for: cameras[1].id) == .sub)
        #expect(viewModel.isHero(cameraId: cameras[0].id) == true)
        #expect(viewModel.isHero(cameraId: cameras[1].id) == false)
    }

    @Test("returnToGrid restores the hero camera to sub quality")
    func returnToGrid() async {
        let cameras = [Camera(displayName: "A", lanIP: "192.0.2.10")]
        let log = LifecycleLog()
        let viewModel = StreamViewModel { camera, quality in
            FakeStreamSession(camera: camera, quality: quality, log: log)
        }
        viewModel.startGrid(cameras: cameras)
        viewModel.enterHero(camera: cameras[0])
        viewModel.returnToGrid(cameras: cameras)

        #expect(viewModel.quality(for: cameras[0].id) == .sub)
        #expect(viewModel.isHero(cameraId: cameras[0].id) == false)
    }

    @Test("stopAll calls stop() on every active session — popover onDisappear contract")
    func stopAll() async {
        let cameras = [
            Camera(displayName: "A", lanIP: "192.0.2.10"),
            Camera(displayName: "B", lanIP: "192.0.2.11"),
        ]
        let log = LifecycleLog()
        let viewModel = StreamViewModel { camera, quality in
            FakeStreamSession(camera: camera, quality: quality, log: log)
        }
        viewModel.startGrid(cameras: cameras)
        viewModel.stopAll()

        #expect(viewModel.activeSessionCount() == 0)
        // FakeStreamSession.stop() records to an actor asynchronously — let those tasks drain.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let stops = await log.events.filter { if case .stopped = $0 { return true } else { return false } }
        #expect(stops.count == 2)
    }

    @Test("Removing a camera from the list stops its session on the next startGrid")
    func cameraRemoval() async {
        let camA = Camera(displayName: "A", lanIP: "192.0.2.10")
        let camB = Camera(displayName: "B", lanIP: "192.0.2.11")
        let log = LifecycleLog()
        let viewModel = StreamViewModel { camera, quality in
            FakeStreamSession(camera: camera, quality: quality, log: log)
        }
        viewModel.startGrid(cameras: [camA, camB])
        #expect(viewModel.activeSessionCount() == 2)
        viewModel.startGrid(cameras: [camA])
        #expect(viewModel.activeSessionCount() == 1)
        #expect(viewModel.quality(for: camB.id) == nil)
    }
}

@Suite("CameraTileView aspect ratio per kind (ADR-0001 doorbell-portrait)")
struct CameraTileAspectTests {
    @Test("Doorbell tiles render 9:16, cameras render 16:9")
    func aspectRatio() {
        let doorbell = Camera(displayName: "Door", lanIP: "192.0.2.20", kind: .doorbell)
        let camera = Camera(displayName: "Garden", lanIP: "192.0.2.10", kind: .camera)
        let doorbellTile = CameraTileView(camera: doorbell, state: .playing)
        let cameraTile = CameraTileView(camera: camera, state: .playing)
        #expect(abs(doorbellTile.aspectRatio - 9.0/16.0) < 0.0001)
        #expect(abs(cameraTile.aspectRatio - 16.0/9.0) < 0.0001)
    }
}

// MARK: - Test doubles

actor LifecycleLog {
    enum Event: Sendable, Equatable {
        case attached(cameraId: UUID, quality: StreamQuality)
        case stopped(cameraId: UUID)
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}

final class FakeStreamSession: StreamSession, @unchecked Sendable {
    let camera: Camera
    let quality: StreamQuality
    private let subject = CurrentValueSubject<StreamState, Never>(.idle)
    private let log: LifecycleLog

    var state: AnyPublisher<StreamState, Never> { subject.eraseToAnyPublisher() }

    init(camera: Camera, quality: StreamQuality, log: LifecycleLog) {
        self.camera = camera
        self.quality = quality
        self.log = log
    }

    func attach(to renderTarget: StreamRenderTarget) async throws {
        await log.record(.attached(cameraId: camera.id, quality: quality))
        subject.send(.playing)
    }

    func stop() {
        Task { await log.record(.stopped(cameraId: camera.id)) }
        subject.send(.ended)
    }
}
