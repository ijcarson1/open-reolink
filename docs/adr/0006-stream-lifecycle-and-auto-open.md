# Stream lifecycle tied to popover; auto-open on ring events

Camera **streams** are expensive (each sub-stream is ~230 MB/hour; main-stream from a 4K camera is ~2.7 GB/hour). Running them all 24×7 against three cameras would burn ~16 GB/day. So streams live and die with the popover: the menu-bar popover opens → stream sessions for the visible tiles start → popover closes → all stream sessions tear down. There is no always-on baseline.

**ONVIF event subscriptions** live separately, in the app process, and stay alive while the popover is closed (long-lived held HTTP connections, near-zero idle bandwidth). This is how we still get notified of motion and ring events without any active stream.

**Auto-open**: a doorbell **ring event** programmatically opens the popover, focuses on the Doorbell tile, and starts its stream. The ring is a deliberate human action and the "what's at the door" reaction is the marquee flow — earning the friction. **Motion events do not auto-open** because they fire from passing cars, branches in wind, and shadows; auto-opening on motion would be intolerable in steady state.

## Considered options

- **Always-on streaming** — every camera streams from app launch, popover shows them live. Rejected on bandwidth/battery/heat. The legacy Reolink desktop client behaves this way but it's not what a menu-bar app should do.
- **Stream-on-popover only, no auto-open** — popover open = streams, closed = nothing. Loses the marquee "ring fires, see the visitor" experience.
- **Stream-on-event, no popover involvement** — events trigger a separate floating window; popover stays "ambient". Adds a second window concept for marginal benefit; not worth the UI surface.

## Consequences

- The `MultiStreamManager` (carried over from OpenRing, retargeted) is the popover's lifecycle dependency. SwiftUI's `onAppear`/`onDisappear` on the popover view drive `start()`/`stopAll()`.
- A dedicated `EventCoordinator` lives in the `AppState` (not the popover). It owns `CameraClient.eventStream()` for each configured camera and emits a domain event to the popover layer (auto-open?), notification layer (UNUserNotificationCenter), AI layer, and persistence layer.
- The app process must remain alive when the popover is closed for events to fire. `LSUIElement = YES` (inherited from OpenRing). No idle-quit policy.
- A user setting `auto_open_on_ring: bool` (default `true`) lets users disable the auto-open if they find it intrusive.
- macOS sleep kills the ONVIF subscriptions' TCP connections. On wake, the `EventCoordinator` re-subscribes from scratch. **Events that fired during sleep are accepted as lost in v1** — Reolink ONVIF does not replay missed events, and the CGI `cmd=Search` backfill that could close the gap is deferred to v1.1.
- **Notification preferences are user-configurable in v1.** Settings expose per-camera toggles plus a global filter on event kinds: `notify_on_ring: bool` (default true), `notify_on_motion: 'none' | 'ai_classified' | 'all'` (default `'ai_classified'` so passing cars don't notify, but a person at the back gate does). Auto-open-on-ring is independent of notification toggles — they're decoupled settings.
- This collapses the original "B vs C" framing — C is structurally B with the auto-open trigger layered on top, not a distinct architecture. Implementation order is: B first end-to-end, then auto-open as an additive trigger.
