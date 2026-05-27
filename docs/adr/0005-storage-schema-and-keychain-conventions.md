# Storage schema and Keychain conventions

The v1 storage layer is three GRDB-managed SQLite tables (`cameras`, `events`, `settings`) plus per-camera Keychain entries for the two passwords each camera requires. The schema deliberately omits `clips`, `snapshots`, `rules`, and `webhooks` from the forked OpenRing schema — none of those earn their keep in v1, and reintroducing any of them is a v1.1+ ADR rather than a slot held empty.

Per ADR-0001 (protocol abstraction with one impl), nothing in the schema is Reolink-specific by *name* — the columns model the abstract `Camera` and `Event` domain types, not a particular vendor's wire schema. `capabilities_json` is the one untyped slot where vendor-specific capability flags accumulate.

## Schema

`cameras (id, display_name, lan_ip, cgi_scheme, cgi_port, rtsp_port, onvif_port, kind, model, firmware_version, admin_username, events_username, capabilities_json, discovered_via, last_seen_at, is_online, created_at, updated_at)`

`events (id, camera_id, kind, ai_class, onvif_topic, occurred_at, received_at, snapshot_path, ai_summary, important, clip_url)` with `(camera_id, occurred_at DESC)` and `(kind)` indexes.

`settings (key, value)` for app-wide K/V (`event_retention_days`, polling intervals, AI enablement, etc.).

Notable shape choices:
- `kind` is `'motion' | 'ring'` only. AI classification (`person | vehicle | animal | null`) goes in `ai_class` so "all motion events" queries don't have to OR across the AI subtypes.
- `clip_url` is nullable in v1 and never populated; v1.1 fills it without a schema migration.
- `events_username` is non-default (no fallback). The setup guide nudges toward "onvif" but the name is arbitrary — only the **role** matters (non-`admin` account used for ONVIF event subscription).
- `lan_ip` is IPv4 only. Validation rejects hostnames at input time per the constraint in CONTEXT.md.
- `discovered_via` records whether the row came from the discovery wizard or manual entry. Future re-discovery on IP change (v1.1+) uses this to know which rows can be auto-updated.

## Keychain conventions

Two Keychain entries per camera, keyed by **role** not username:

- Service: `dev.open-reolink`
- Account: `<cameraId>.admin` — password for the `admin_username` (CGI snapshot, spotlight, quick-reply)
- Account: `<cameraId>.events` — password for the `events_username` (ONVIF Pull-Point subscription)

When a camera is deleted, both Keychain entries are deleted.

## Migrations

`v1_reolink_initial` creates all three tables in one migration. The forked OpenRing migrations (`v1_initial`, `v2_ai_description`) are **deleted** rather than amended — this is a clean break with no production users to preserve. The DB file path also changes: from `~/Library/Application Support/open-ring/open-ring.db` to `~/Library/Application Support/open-reolink/open-reolink.db`, so an existing OpenRing install's data is left alone.

## Consequences

- The `Camera` Swift type has two `password` accessors (`adminPassword`, `eventsPassword`) that read from Keychain on demand. The struct itself is `Codable` and DB-mappable without ever holding plaintext.
- A `CameraRepository` (GRDB DAO) handles row CRUD; a separate `CredentialStore` (Keychain wrapper) handles password CRUD. Deleting a camera goes through a `CameraService` that coordinates both — never just one.
- `capabilities_json` is decoded into a typed `CameraCapabilities` struct at read time; the column stays as TEXT so we never block on a schema migration when a new capability is detected.
