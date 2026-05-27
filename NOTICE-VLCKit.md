# VLCKit notice (LGPL §6 compliance)

This application uses **VLCKit**, distributed under the GNU Lesser General Public License (LGPL).

- **Upstream source:** https://code.videolan.org/videolan/VLCKit
- **License (LGPL):** https://www.gnu.org/licenses/lgpl-2.1.html
- **Stable binaries:** https://download.videolan.org/pub/cocoapods/prod/

## How VLCKit is linked

VLCKit is **dynamically** linked into the application as a binary framework. Static linking is not permitted under LGPL without GPL contamination.

## Replacing VLCKit

The application's RTSP playback is encapsulated in `ReolinkRTSPSession` (in the `ReolinkClient` Swift package). Anyone wishing to relink or replace VLCKit can:

1. Download the official VLCKit source from the upstream URL above.
2. Build VLCKit on macOS using the upstream build instructions.
3. Replace the VLCKit framework bundled with this application.

The application will continue to function identically with any binary-compatible VLCKit build.

## Source-on-request

A copy of the unmodified VLCKit source corresponding to the binary linked in this application is available on request — file an issue on this repository.
