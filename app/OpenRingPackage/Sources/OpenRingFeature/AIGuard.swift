import Foundation
import Combine
import ReolinkClient
import Storage
import VisionProviders

public struct AISummary: Sendable, Identifiable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case ok(text: String)
        case failure(message: String)
        case rateLimited
    }
    public let id = UUID()
    public let eventId: UUID
    public let cameraId: UUID
    public let outcome: Outcome
}

/// Policy gate + executor for AI analysis on Camera events.
///
/// Per ADR-0007 the v1 policy is:
///   - Ring events: always (when an `ai_provider` is configured)
///   - Motion events with `ai_class`: only when the user opts in
///     (Slice 7 setting; defaults to false here)
///   - All other events: never
///
/// Rate-limited via `RateLimiter` (per-camera token bucket; default 1/min
/// per ADR-0007). `analyzeEvent` returns the outcome instead of `throw`ing
/// so the UI can render success / failure / rate-limited paths uniformly.
public actor AIGuard {
    public struct Snapshot: Sendable {
        public let jpeg: Data
    }

    public var motionAIEnabled: Bool

    private let snapshotProvider: @Sendable (Camera) async throws -> Data
    private let providerResolver: @Sendable () -> VisionProvider?
    private let rateLimiter: RateLimiter

    public init(
        motionAIEnabled: Bool = false,
        snapshotProvider: @escaping @Sendable (Camera) async throws -> Data,
        providerResolver: @escaping @Sendable () -> VisionProvider?,
        rateLimiter: RateLimiter = RateLimiter()
    ) {
        self.motionAIEnabled = motionAIEnabled
        self.snapshotProvider = snapshotProvider
        self.providerResolver = providerResolver
        self.rateLimiter = rateLimiter
    }

    public func setMotionAIEnabled(_ enabled: Bool) {
        motionAIEnabled = enabled
    }

    public func setRateCap(_ cap: Int) {
        rateLimiter.setCapacity(cap)
    }

    /// Routing gate — exposed for testing. Returns true when this event
    /// should be sent to the active VisionProvider.
    public func shouldAnalyze(event: CameraEvent) -> Bool {
        switch event.kind {
        case .ring:
            return providerResolver() != nil
        case .motion:
            return motionAIEnabled && event.aiClass != nil && providerResolver() != nil
        }
    }

    public func analyzeEvent(_ event: CameraEvent, on camera: Camera) async -> AISummary? {
        guard shouldAnalyze(event: event) else { return nil }
        guard rateLimiter.tryConsume(key: camera.id.uuidString) else {
            return AISummary(eventId: event.id, cameraId: camera.id, outcome: .rateLimited)
        }
        guard let provider = providerResolver() else { return nil }
        do {
            let jpeg = try await snapshotProvider(camera)
            let text = try await provider.analyze(jpeg: jpeg, prompt: Self.prompt(for: event))
            return AISummary(eventId: event.id, cameraId: camera.id, outcome: .ok(text: text))
        } catch {
            return AISummary(
                eventId: event.id,
                cameraId: camera.id,
                outcome: .failure(message: Self.describe(error))
            )
        }
    }

    private static func prompt(for event: CameraEvent) -> String {
        switch event.kind {
        case .ring:
            return "Someone has rung this doorbell. In one sentence, describe who or what appears to be in the image."
        case .motion:
            if let aiClass = event.aiClass {
                return "Camera detected motion classified as \(aiClass). Briefly describe what's happening in this snapshot."
            }
            return "Briefly describe what's happening in this snapshot."
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case VisionProviderError.unauthorized:
            return "AI provider rejected the API key."
        case VisionProviderError.rateLimited:
            return "AI provider rate limit reached. Try again shortly."
        case VisionProviderError.serverError(let status):
            return "AI provider returned HTTP \(status)."
        case VisionProviderError.transport(let detail):
            return "AI provider unreachable: \(detail)"
        case VisionProviderError.malformedResponse:
            return "AI provider returned an unexpected response."
        default:
            return "AI provider failed: \(error.localizedDescription)"
        }
    }
}
