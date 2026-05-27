#!/usr/bin/env bash
# Download and install VLCKit.xcframework for open-reolink.
#
# The xcframework is ~409 MB extracted (~88 MB compressed) so it's not
# committed to git. Run this once after cloning, and again whenever the
# pinned VLCKit version changes.
#
# Source: https://download.videolan.org/pub/cocoapods/prod/
# License: LGPL — see NOTICE-VLCKit.md for §6 compliance.
#
# Usage: ./scripts/setup-vlckit.sh

set -euo pipefail

# Pinned VLCKit version (latest stable as of 2026-02-25). To upgrade, find a
# newer tarball at https://download.videolan.org/pub/cocoapods/prod/ and
# update both VERSION and EXPECTED_SHA256.
VERSION="3.7.3-319ed2c0-79128878"
URL="https://download.videolan.org/pub/cocoapods/prod/VLCKit-${VERSION}.tar.xz"
EXPECTED_SHA256="019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="$ROOT/app/OpenRingPackage/Frameworks"
TARGET="$FRAMEWORK_DIR/VLCKit.xcframework"

if [ -d "$TARGET" ] && [ "${1:-}" != "--force" ]; then
  echo "VLCKit.xcframework already present at:"
  echo "  $TARGET"
  echo "Pass --force to redownload."
  exit 0
fi

mkdir -p "$FRAMEWORK_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE="$TMP_DIR/VLCKit.tar.xz"
echo "Downloading VLCKit ${VERSION}..."
curl -L --fail --progress-bar -o "$ARCHIVE" "$URL"

echo "Verifying SHA-256..."
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "FAIL: checksum mismatch"
  echo "  expected: $EXPECTED_SHA256"
  echo "  got:      $ACTUAL_SHA256"
  exit 1
fi

echo "Extracting..."
tar -xf "$ARCHIVE" -C "$TMP_DIR"

# The tarball expands as "VLCKit - binary package/VLCKit.xcframework"
SRC_XCFRAMEWORK="$TMP_DIR/VLCKit - binary package/VLCKit.xcframework"
if [ ! -d "$SRC_XCFRAMEWORK" ]; then
  echo "FAIL: expected VLCKit.xcframework not found in archive"
  exit 1
fi

rm -rf "$TARGET"
mv "$SRC_XCFRAMEWORK" "$TARGET"

echo
echo "VLCKit installed:"
echo "  $TARGET"
echo
echo "Next: build the app —"
echo "  cd app && xcodebuild -scheme OpenRing -destination 'platform=macOS,arch=arm64' build"
