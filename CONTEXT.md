# open-reolink

A macOS menu-bar client that talks directly to Reolink cameras and doorbells over the local network. No cloud, no broker, no Home Assistant — the Mac speaks to each device by IP.

## Language

**Camera**:
A single Reolink device on the LAN, identified by IP/host and per-device credentials. Includes still cameras and doorbells.
_Avoid_: Device, hub, entity.

**Doorbell**:
A subtype of **Camera** that additionally supports a press event ("ring") and two-way audio. Currently the Reolink Video Doorbell PoE.
_Avoid_: Front-door camera.

**Stream**:
A live video feed from a **Camera**. Pulled directly from the camera over LAN.
_Avoid_: Broadcast, feed, live view (the old Ring term).

**Snapshot**:
A single still frame fetched on demand from a **Camera**. Cheaper than starting a **Stream**.

**Motion event**:
A timestamped notification that a **Camera** detected motion. Sourced from the camera itself, not from any external system.
_Avoid_: Ding (the old Ring term), alert, notification.

**Ring event**:
A timestamped notification that a **Doorbell**'s button was pressed. Distinct from a **Motion event** — a doorbell can produce either.
_Avoid_: Ding, press.

**Quick reply**:
A pre-recorded audio message stored on a **Doorbell** that the user can trigger from the app to play through the doorbell's speaker. The interaction replacement for two-way audio (which we're not building in v1).
_Avoid_: Voice reply, canned response, auto-reply.

**Vision provider**:
A third-party service that turns a JPEG snapshot + a prompt into a text answer. v1 supports Anthropic and OpenAI; the user picks one in settings, or none (AI off).
_Avoid_: AI, LLM, model — when the conversation is about wiring/configuration, "vision provider" is the specific term.

**AI summary**:
The text returned by a **Vision provider** for a **Motion event** or **Ring event**. Stored per-event in `events.ai_summary`. Null when AI is off or the call failed.
_Avoid_: Description, caption.

## Relationships

- The user has many **Camera**s. Currently three: one **Doorbell** and two non-doorbell **Camera**s.
- A **Camera** produces zero or more **Motion event**s over time.
- A **Doorbell** produces zero or more **Motion event**s AND zero or more **Ring event**s.
- A **Stream** belongs to exactly one **Camera** and is live (not historical).

## Constraints

- **A Camera is identified by IP**, not hostname. Mixed-DHCP + mDNS resolution is out of scope; the user is expected to set a DHCP reservation on the router, or use the camera's built-in static-IP setting.
- **Configuration is local to the Mac it runs on.** No cloud account, no sync. A user with two Macs configures each independently. Camera-list export/import is a separate manual action, not a synced state.
- **Camera passwords live in the macOS Keychain**, one entry per Camera, keyed by Camera ID. The Camera record itself (host, port, display name, type, capabilities) lives in GRDB.
- **Each Camera has TWO accounts in Reolink firmware: `admin` (Administrator, used for CGI / snapshot / spotlight / quick-reply) and a user-created Administrator/User-level account for ONVIF.** Reolink only allows one Administrator slot, reserved for `admin`. Onboarding must walk the user through creating an additional User-level account (any name; "onvif" is the convention) before ONVIF event subscription can succeed.
- **Reolink cameras enforce "Illegal Login Lockout" by default**: repeated auth failures within 3 minutes lock the account for several minutes. The client must cap auth retries at 3 with exponential backoff and surface a user-facing "wait ~5 min" message instead of retrying further.

## Flagged ambiguities

- "Ring" — the brand name of the original codebase AND a doorbell-press event. We've renamed the latter to **Ring event** and reserve "Ring" for git history only.

## Example dialogue

> **Dev:** "When a **Doorbell** is pressed, do we open a **Stream** automatically?"
> **Designer:** "We open the most recent **Snapshot** in the menu bar pop-out, and the user clicks to start the **Stream**. Streams cost bandwidth and we don't want one running every time someone walks past."
