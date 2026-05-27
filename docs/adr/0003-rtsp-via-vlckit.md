# Stream playback via VLCKit, not FFmpegKit

Reolink cameras on LAN expose video over RTSP only — AVFoundation does not support RTSP, so we need a third-party library. We chose **VLCKit** despite the heavier binary footprint (~30 MB) because the obvious alternative, **`arthenica/ffmpeg-kit`**, was officially archived in 2025 with the README stating "FFmpegKit has been officially retired. There will be no further `ffmpeg-kit` releases" and pre-built binaries removed from distribution. The remaining FFmpeg paths (community forks, hand-rolled SwiftFFmpeg bindings, or building a custom `xcframework`) all add real maintenance burden a single-developer project can't justify in v1.

## Considered options

- **FFmpegKit (arthenica)** — would have been first choice (smaller, thinner wrapper, more control over the decode pipeline). Archived; not adoptable in a new 2026 project.
- **Community fork of ffmpeg-kit** — pin risk; forks vary in quality; macOS-arm64 support uneven.
- **SwiftFFmpeg + bundled FFmpeg dylibs / custom xcframework** — technically the right long-term answer for binary size and notarization, rejected for v1 because of the time cost of writing/maintaining the demux→decode→`AVSampleBufferDisplayLayer` pipeline ourselves.
- **VLCKit** — chosen. Mature, native macOS arm64 universal binary, MIT/LGPL, handles every Reolink RTSP quirk (H.264 + H.265 + AAC, reconnect, codec negotiation) out of the box.

## Consequences

- Binary size grows by ~30 MB. Acceptable for a desktop menu-bar app.
- The `StreamSession` protocol (per ADR-0001) hides VLCKit behind a vendor-agnostic surface. A future migration away from VLCKit changes one file (`ReolinkRTSPSession`), not the feature layer.
- LGPL means VLCKit must be **dynamically linked** and we ship its source/build-instructions per LGPL §6. Static linking is not permitted without GPL contamination.
- "More control over the decode pipeline" (raw AVPackets for AI keyframe extraction, custom hardware-decode flags) is something we trade away. If a future feature requires it, that's the trigger to revisit this ADR — not before.
