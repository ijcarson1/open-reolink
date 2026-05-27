import Foundation
import ReolinkClient

/// Production `CameraEventSource` that drives the ONVIF Pull-Point loop
/// against a real camera (per ADR-0004).
///
/// Lifecycle per camera:
///   1. CreatePullPointSubscription with a 60s lease
///   2. Schedule Renew at lease-30s
///   3. Long-poll PullMessages with PT30S timeout
///   4. Yield each ONVIFPullMessage to the consumer
///   5. On any error: cancel renew, sleep 5s, restart from step 1
///
/// `notAuthorized` is surfaced as-is so the EventCoordinator's lockout logic
/// can engage (3 consecutive → 5-minute cooldown).
public final class ReolinkONVIFEventSource: CameraEventSource, @unchecked Sendable {
    public init() {}

    public func events(for camera: Camera, password: String) -> AsyncThrowingStream<ONVIFPullMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runLoop(camera: camera, password: password, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runLoop(
        camera: Camera,
        password: String,
        continuation: AsyncThrowingStream<ONVIFPullMessage, Error>.Continuation
    ) async {
        let client = ReolinkONVIFClient(camera: camera, eventsPassword: password)

        while !Task.isCancelled {
            var renewTask: Task<Void, Never>?
            do {
                let subscription = try await client.createPullPointSubscription(timeoutSeconds: 60)
                renewTask = scheduleRenew(client: client, subscription: subscription)

                while !Task.isCancelled {
                    let messages = try await client.pullMessages(from: subscription, timeoutSeconds: 30)
                    for message in messages {
                        continuation.yield(message)
                    }
                }

                renewTask?.cancel()
                try? await client.unsubscribe(subscription)
            } catch ONVIFError.notAuthorized {
                renewTask?.cancel()
                continuation.finish(throwing: ONVIFError.notAuthorized)
                return
            } catch {
                renewTask?.cancel()
                // Transport / parsing error — short backoff and re-subscribe.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        continuation.finish()
    }

    private func scheduleRenew(
        client: ReolinkONVIFClient,
        subscription: ONVIFSubscriptionReference
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                // Subscription lease is 60s; renew at lease-30s.
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { return }
                try? await client.renew(subscription, seconds: 60)
            }
        }
    }
}
