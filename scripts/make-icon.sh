#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the vector source Resources/AppIcon.svg.
#
# The .icns is committed so building the app never needs a renderer; run this only
# after editing AppIcon.svg. Uses only tools that ship with macOS (qlmanage renders
# the SVG, sips resamples, iconutil packs the iconset).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/Resources/AppIcon.svg"
ICNS="$ROOT/Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "==> Rendering $SVG at 1024x1024"
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
MASTER="$WORK/$(basename "$SVG").png"
[[ -f "$MASTER" ]] || { echo "error: qlmanage did not render $SVG" >&2; exit 1; }

# Every size macOS asks for, 1x and 2x.
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$MASTER" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z "$((SIZE * 2))" "$((SIZE * 2))" "$MASTER" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

echo "==> Packing $ICNS"
iconutil --convert icns --output "$ICNS" "$ICONSET"
echo "==> Done: $ICNS"
