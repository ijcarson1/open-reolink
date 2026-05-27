# v1 scope and deferred features

v1 ships **live stream, snapshot, motion events, ring events, multi-camera grid, and AI Q&A on the Doorbell's snapshots**. It deliberately omits push-to-talk, Quick Reply playback, historical clip playback, PTZ control, and floodlight/siren control. The bar we're targeting is parity with the live-monitoring subset of the legacy Reolink macOS desktop client, which is being deprecated on Apple Silicon — that's the user need driving the project, and the rest are "nice-to-haves I rarely reach for" rather than deal-breakers.

The AI feature is **scoped to the Doorbell only** in v1 — "what's at the door" is the load-bearing use case. Generalising AI to non-Doorbell Cameras is deferred; the existing prompt and `VisionAnalyzer` are already byte-generic over JPEG, so this is a UI/prompt scope decision not a code one.

## Considered options

- **Push-to-talk**: Reolink's two-way audio rides a proprietary binary protocol ("Baichuan") that is undocumented and would be a multi-week port. Defer indefinitely; Quick Reply (also deferred to v1.1) gives most of the doorbell-interaction value when added.
- **Quick Reply playback**: pre-recorded audio messages exposed via standard HTTP CGI. Cheap to port (~100 LOC) — but not a v1 unlock. Moved to v1.1 with the rest of the polish features.
- **Historical clip playback**: requires a timeline UI, calendar picker, scrubber, and clip-search API. SD cards exist in the cameras, so the data is there when we want it. Schema leaves a nullable `clip_url` slot from day one so v1.1 is purely a UI add — no migration.
- **PTZ on Cameras that support it** (e.g. E1 Zoom): cheap CGI commands (`cmd=PtzCtrl`). Deferred to v1.1 to keep v1 focused.
- **Floodlight + siren on Cameras that have them** (e.g. Duo 3 PoE): also cheap CGI. Deferred to v1.1.

## Consequences

- The `events` schema must allow nullable `clip_url` from the first migration so v1.1 can populate it without a schema change.
- The `cameras` schema must store `capabilities_json` so the UI can reason about per-model differences (PTZ, spotlight, ring) once those features land — without a schema change in v1.1.
- We **do not** ship anything that requires Reolink's Baichuan protocol. If a feature needs it, that feature is post-v1.1 and gets its own ADR.
- The AI-on-doorbell wiring stays in `OpenRingFeature` and is wired only to the Doorbell tile. Other Camera tiles do not surface an AI affordance in v1.
