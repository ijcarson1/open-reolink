# Motion + Ring events via ONVIF Pull-Point Subscription

We get motion events and doorbell-ring events from each Camera by holding an **ONVIF Pull-Point Subscription** open per camera. The Mac creates a subscription via `CreatePullPointSubscription` against the Events service, then issues long-running `PullMessages` calls on the per-subscription URL. The camera holds each PullMessages connection open until either an event fires or the timeout (we use `PT30S`) elapses, at which point the client immediately re-issues the call.

The realistic alternative was **Reolink's HTTP CGI** (`cmd=GetMdState` long-polling every 1-2s). It would have been simpler — no SOAP, no WSE, no WS-Addressing — and Reolink's web/mobile clients use it. We rejected it on two axes: (a) latency: 1-2s polling is too slow for a doorbell ring; pull-point fires sub-second; (b) load: N cameras × 30 req/min of CGI polling vs N held connections regardless of motion rate.

## Reolink-firmware constraints we discovered the hard way

Documented here because the next person to touch this code will hit them blind.

- **A non-`admin` account is required.** The built-in `admin` Administrator account returns `ter:NotAuthorized` over ONVIF on this firmware (v3.0.0.4518 on Duo 3 PoE, tested 2026-05-27). Any non-`admin`-named account, created at User level, authenticates fine. Reolink only allows one Administrator slot (reserved for `admin`), so in practice the second account is User-level. The name itself is irrelevant — onboarding documentation suggests "onvif" as a convention but doesn't enforce it.
- **Reolink ONVIF accepts only `PasswordDigest` auth.** `PasswordText` returns HTTP 400 ("malformed request"). The client uses Digest exclusively.
- **The per-subscription URL requires WS-Addressing headers.** `CreatePullPointSubscription` against the Events service URL works without them; subsequent `PullMessages` / `Renew` / `Unsubscribe` calls against the returned subscription URL require `wsa:To` + `wsa:Action` + `wsa:MessageID` headers or the camera returns HTTP 400.
- **"Illegal Login Lockout" is on by default**: 3 failed auth attempts within 3 minutes locks the account for ~5 minutes. The client caps retries at 3 and surfaces a clear "wait ~5 min" error rather than auto-retrying.
- **Only `admin` can use Reolink CGI for snapshots/spotlight/quick-reply.** So each Camera record actually carries **two credentials**: the `admin` password (for CGI), and the user-level ONVIF password (for events). Both live in Keychain, keyed by `cameraId`.

## Consequences

- The codebase needs a small ONVIF SOAP client (~300 LOC: envelope builder, WSE digest header, WSA headers, response parsing for 5 operations: `Probe`, `GetCapabilities`, `GetDeviceInformation`, `CreatePullPointSubscription`, `PullMessages`). We do not import a generic SOAP library — too much surface for too little benefit.
- A subscription must be **renewed** before its lease expires. We use 60-second leases and renew at 30s; if renewal fails, we recreate from scratch.
- The discovery wizard's onboarding flow links to a setup guide explaining how to add the second account via the camera's *web dashboard* (`https://<camera-ip>/`). Users *cannot* skip this step — without a non-`admin` account ONVIF events don't work. The app does NOT auto-create the account via CGI; we treat camera-user-management as a deliberate user action.
- If a future Reolink firmware fixes the `admin`-over-ONVIF issue, we can simplify the two-credentials-per-camera model. Tracked as a follow-up; for now both are required.
