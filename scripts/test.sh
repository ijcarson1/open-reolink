#!/usr/bin/env bash
# Wrapper around `swift test` that symlinks VLCKit.framework into the xctest
# bundle so dlopen can find it.
#
# Why this exists: SwiftPM's binaryTarget compiles + links fine, and the Xcode
# app build embeds the framework correctly. But `swift test` does NOT embed
# binaryTargets into the test xctest bundle, so the test runner can't
# resolve the framework at load time.
#
# Usage: ./scripts/test.sh [extra `swift test` args...]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/app/OpenRingPackage"
cd "$PACKAGE"

# Initial build is needed to create the .xctest bundle dir
swift build --build-tests >/dev/null 2>&1 || true

XCTEST=".build/arm64-apple-macosx/debug/OpenRingPackagePackageTests.xctest"
if [ -d "$XCTEST" ]; then
  FW_DIR="$XCTEST/Contents/Frameworks"
  mkdir -p "$FW_DIR"
  ln -sfn \
    "$PACKAGE/Frameworks/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework" \
    "$FW_DIR/VLCKit.framework"
fi

exec swift test "$@"
