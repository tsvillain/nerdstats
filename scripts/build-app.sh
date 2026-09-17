#!/usr/bin/env bash
# Builds NerdStats as a universal (arm64 + x86_64) binary with SwiftPM and wraps it in
# an .app bundle at build/NerdStats.app.
#
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/NerdStats.app"

cd "$ROOT"
echo "==> Building universal $CONFIGURATION binary"
swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --product NerdStats
BINARY="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)/NerdStats"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/NerdStats"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS accepts the bundle locally (and SMAppService can register it).
# This is not a distribution signature; Developer ID signing and notarization come later.
codesign --force --sign - "$APP"

lipo -info "$APP/Contents/MacOS/NerdStats"
echo "==> Done: $APP"
