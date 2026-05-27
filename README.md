<h1 align="center">open-reolink</h1>

<p align="center">
  <strong>A native macOS menu-bar client for Reolink LAN cameras.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.1+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

## What this is

A SwiftUI menu-bar app that talks directly to Reolink cameras and doorbells on the local network. No cloud account, no Home Assistant runtime dependency, no browser. Replaces the deprecated Reolink desktop client on Apple Silicon Macs.

- Sub-second RTSP streams via [VLCKit](https://code.videolan.org/videolan/VLCKit)
- Snapshot + admin operations via Reolink HTTP CGI (HTTPS, self-signed-cert tolerant)
- Motion + ring events via ONVIF Pull-Point Subscriptions
- WS-Discovery onboarding for new cameras
- Optional opt-in AI summaries (Anthropic Claude or OpenAI) on doorbell events
- LAN-only — IPv4 addressing, two credentials per camera (admin + non-admin ONVIF user)

## Status

v1 development. The architecture is locked in seven ADRs under [`docs/adr/`](docs/adr/). The domain glossary lives in [`CONTEXT.md`](CONTEXT.md). Setup walkthrough at [`docs/reolink-setup-guide.md`](docs/reolink-setup-guide.md).

## Hardware verified

Confirmed working against:
- Reolink Duo 3 PoE (firmware v3.0.0.4518) — H.265, AI person/vehicle classification, ONVIF events
- Reolink E1 Zoom — H.264, ONVIF events
- Reolink Video Doorbell PoE — ring events, two-way audio (deferred)

Other Reolink models should work but are unverified; please report back.

## Architecture

- **`ReolinkClient`** — `CameraClient` protocol, `ReolinkCGIClient` (snapshot via HTTPS CGI), `ReolinkRTSPSession` (VLCKit), `ReolinkONVIFClient` (event subscriptions). Hand-rolled `ONVIFSoap` deep module with PasswordDigest auth + WS-Addressing.
- **`Storage`** — GRDB-backed `cameras`, `events`, `settings` tables. `CameraRepository`, `EventRepository`, `SettingsRepository`. Two-passwords-per-camera in Keychain (`<cameraId>.admin` + `<cameraId>.events`), service `dev.open-reolink`. `CameraService` is the single mutation point for the cross-store delete cascade.
- **`VisionProviders`** — `VisionProvider` protocol with `AnthropicVisionProvider` + `OpenAIVisionProvider`. `VisionProviderRegistry` reads the active provider from settings.
- **`OpenRingFeature`** — `AppState`, `SnapshotPopoverView`, `OnboardingWizardView`, `SettingsView`, `EventCoordinator`, `AIGuard`, `NotificationManager`, `StreamViewModel`.
- **`DesignSystem`** — fonts, colors, components.

## Build

```bash
cd app
xcodebuild -scheme OpenRing -destination 'platform=macOS,arch=arm64' build
```

VLCKit must be added to the Xcode project as a dynamically-linked binary xcframework. Download from [download.videolan.org/pub/cocoapods/prod/](https://download.videolan.org/pub/cocoapods/prod/). See [`NOTICE-VLCKit.md`](NOTICE-VLCKit.md) for LGPL §6 compliance notes.

## License

MIT. Contributions welcome.
