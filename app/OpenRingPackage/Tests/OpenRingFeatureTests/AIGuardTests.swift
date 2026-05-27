import Foundation
import Testing
import ReolinkClient
import VisionProviders
@testable import OpenRingFeature

@Suite("AIGuard gating + rate cap")
struct AIGuardTests {

    @Test("Ring events with a configured provider pass the gate")
    func ringPasses() async {
        let guardActor = makeGuard()
        let event = CameraEvent(cameraId: UUID(), kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        #expect(await guardActor.shouldAnalyze(event: event) == true)
    }

    @Test("Bare motion is blocked even when a provider is configured")
    func bareMotionBlocked() async {
        let guardActor = makeGuard()
        let event = CameraEvent(cameraId: UUID(), kind: .motion, aiClass: nil, topic: "motion", occurredAt: Date())
        #expect(await guardActor.shouldAnalyze(event: event) == false)
    }

    @Test("AI-classified motion is gated by motionAIEnabled (off by default)")
    func motionGatedByToggle() async {
        let guardActor = makeGuard()
        let event = CameraEvent(cameraId: UUID(), kind: .motion, aiClass: "person", topic: "motion", occurredAt: Date())
        #expect(await guardActor.shouldAnalyze(event: event) == false)
        await guardActor.setMotionAIEnabled(true)
        #expect(await guardActor.shouldAnalyze(event: event) == true)
    }

    @Test("With ai_provider=.none nothing passes the gate")
    func noProviderBlocks() async {
        let guardActor = AIGuard(
            snapshotProvider: { _ in Data() },
            providerResolver: { nil },
            rateLimiter: RateLimiter(capacity: 1)
        )
        let event = CameraEvent(cameraId: UUID(), kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        #expect(await guardActor.shouldAnalyze(event: event) == false)
    }

    @Test("Rate limiter blocks the second ring in the same minute, returning .rateLimited")
    func rateLimitWithinWindow() async {
        let guardActor = makeGuard(rateCap: 1)
        let camera = Camera(displayName: "Front door", lanIP: "192.0.2.10", kind: .doorbell)
        let ring1 = CameraEvent(cameraId: camera.id, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        let ring2 = CameraEvent(cameraId: camera.id, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        let firstOutcome = await guardActor.analyzeEvent(ring1, on: camera)
        let secondOutcome = await guardActor.analyzeEvent(ring2, on: camera)
        if case .ok = firstOutcome?.outcome {
            #expect(true)
        } else {
            Issue.record("expected .ok on first, got \(String(describing: firstOutcome?.outcome))")
        }
        if case .rateLimited = secondOutcome?.outcome {
            #expect(true)
        } else {
            Issue.record("expected .rateLimited on second, got \(String(describing: secondOutcome?.outcome))")
        }
    }

    @Test("Provider failure surfaces as .failure outcome (snapshot remains, event uncoupled)")
    func providerFailureNoCoupling() async {
        let guardActor = AIGuard(
            snapshotProvider: { _ in Data([0xFF, 0xD8, 0xFF]) },
            providerResolver: { FailingProvider() },
            rateLimiter: RateLimiter(capacity: 1)
        )
        let camera = Camera(displayName: "Front door", lanIP: "192.0.2.10", kind: .doorbell)
        let event = CameraEvent(cameraId: camera.id, kind: .ring, aiClass: nil, topic: "ring", occurredAt: Date())
        let summary = await guardActor.analyzeEvent(event, on: camera)
        if case .failure = summary?.outcome {
            #expect(true)
        } else {
            Issue.record("expected .failure, got \(String(describing: summary?.outcome))")
        }
    }

    // MARK: - factory

    private func makeGuard(rateCap: Int = 10, motionAIEnabled: Bool = false) -> AIGuard {
        AIGuard(
            motionAIEnabled: motionAIEnabled,
            snapshotProvider: { _ in Data([0xFF, 0xD8, 0xFF]) },
            providerResolver: { OkayProvider() },
            rateLimiter: RateLimiter(capacity: rateCap, refillInterval: 60)
        )
    }
}

private struct OkayProvider: VisionProvider {
    var displayName: String { "ok" }
    func analyze(jpeg: Data, prompt: String) async throws -> String {
        "A summary."
    }
}

private struct FailingProvider: VisionProvider {
    var displayName: String { "fail" }
    func analyze(jpeg: Data, prompt: String) async throws -> String {
        throw VisionProviderError.serverError(500)
    }
}
