# AI is opt-in and supports multiple providers

The "ask AI what's at the door" feature is part of v1's parity bar with OpenRing — it's a marquee feature, not an experiment — but it is **strictly opt-in**: a user with no AI key configured uses the rest of the app without any prompts, nags, or degraded UI. The Doorbell tile shows snapshots and live stream; the "Ask AI" affordance simply isn't drawn until a key exists. This matches the project's goal-B audience (anyone with Reolink gear) without forcing them to also acquire an AI provider account.

v1 supports **two AI providers**, user picks one: **Anthropic Claude** (the existing OpenRing wiring, ported) and **OpenAI** (referred to colloquially as "Codex" in user conversation, but the API endpoint is `api.openai.com`). Both have vision-capable models with comparable quality for this use case; the wire shapes differ enough to need a real abstraction, not a parameterised URL.

A `VisionProvider` protocol with two implementations (`AnthropicVisionProvider`, `OpenAIVisionProvider`) sits between `AIGuard` / `VisionAnalyzer` and the provider's HTTP API. The protocol surface is minimal:

```swift
protocol VisionProvider {
    var displayName: String { get }
    func analyze(jpeg: Data, prompt: String) async throws -> String
}
```

Per ADR-0001, the abstraction shape is *narrow* — we only model what both providers need. If a third provider lands (Gemini? local Ollama?), it adds an implementation, not a new layer.

## Considered options

- **Single-provider (Anthropic only)**, matching the OpenRing fork — rejected because the primary user wants to use their existing OpenAI key, and forcing them to maintain a second AI subscription for one feature is unreasonable.
- **Provider abstraction with three v1 impls (Anthropic + OpenAI + local Ollama)** — rejected; local-vision adds binary-bundling complexity (a 4-7 GB model file) and a slow CPU-bound code path. Defer indefinitely; the protocol allows adding it later without churn.
- **Make AI required, fail onboarding without a key** — rejected; bisects the project's goal-B audience for marginal benefit. The existing OpenRing was already AI-as-feature, not AI-as-requirement.

## Consequences

- **Keychain layout**: one slot per supported provider, addressable by `dev.open-reolink.ai.<provider>` (e.g. `dev.open-reolink.ai.anthropic`, `dev.open-reolink.ai.openai`). Switching providers in settings does not delete the other's key — round-tripping is free.
- **Settings entry**: `ai_provider: 'none' | 'anthropic' | 'openai'`, default `'none'`. Onboarding does **not** prompt for an AI key — the user discovers and enables it via settings on their own time.
- **Rate limiting** is a per-provider in-memory token bucket. Default cap: 1 AI call per minute per camera (configurable). Hard cap prevents a stuck-motion scenario (e.g. tree branch in wind) from burning the user's quota in a single afternoon.
- **Failure mode**: when an AI call fails (network, rate limit, billing, model error), the event still gets the snapshot and notification — `ai_summary` stays NULL. The "Ask AI" button reflects the error inline ("AI temporarily unavailable") and the user can retry. No retries are automatic.
- **Prompt** is provider-agnostic: same string handed to both, formatted into each provider's content-block shape inside the implementation. Different models will produce different prose; we accept that as the cost of choice.
- **The existing `AIGuard` and `VisionAnalyzer` are refactored** rather than replaced. `AIGuard` keeps its current responsibilities (deciding which events warrant AI). `VisionAnalyzer` becomes a thin orchestrator that fetches the snapshot via the active `CameraClient`, then hands JPEG + prompt to the active `VisionProvider`.
