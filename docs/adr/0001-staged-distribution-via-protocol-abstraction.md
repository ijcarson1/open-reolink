# Staged distribution via a single-impl protocol abstraction

The long-term goal is an open-source Reolink client analogous to OpenRing — any user can install it and point it at their gear. The short-term reality is one developer's specific hardware (1× E1 Zoom, 1× Duo 3 PoE, 1× Video Doorbell PoE, no NVR, all on LAN). We're shipping for the short-term first, but introducing a `StreamSession`/`CameraClient` protocol abstraction on day one with a single Reolink-LAN implementation behind it.

The trade-off is real: writing the protocol now is overhead with no immediate benefit, and "abstraction with one implementation" is the canonical YAGNI smell. We accepted that cost because the Ring codebase we forked inlined Ring-specific calls into 11 feature-layer files, which is exactly the trap we want to avoid — and because we know a second implementation is coming (NVR-backed, cloud-relay, or just second-vendor support after MVP).

## Consequences

- Feature-layer code (`OpenRingFeature/`) must never import a Reolink-specific type. It works against the protocol.
- The protocol surface is allowed to be narrow at first — only what the current single impl needs. We grow it when the second impl forces it, not speculatively.
- This ADR is the licence to delete the abstraction if, after the second impl lands, the protocol turns out to have been wrong-shape. The decision to *have* one is recorded; the specific shape isn't.
