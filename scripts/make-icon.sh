#!/usr/bin/env bash
#
# Regenerates the app icon from branding/tabs-icon.svg.
# The SVG paints a full-bleed opaque field, so rsvg-convert emits an opaque PNG
# with no alpha channel — which is what App Store icons require. The script
# asserts that and fails loudly if a future SVG edit reintroduces transparency.
#
# Requires: rsvg-convert (`brew install librsvg`).
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$DIR/branding/tabs-icon.svg"
OUT="$DIR/Tabs/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

if ! command -v rsvg-convert >/dev/null; then
  echo "rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

rsvg-convert -w 1024 -h 1024 "$SVG" -o "$OUT"

if sips -g hasAlpha "$OUT" | grep -q "hasAlpha: yes"; then
  echo "ERROR: $OUT has an alpha channel; App Store icons must be opaque." >&2
  echo "Ensure branding/tabs-icon.svg has a full-bleed opaque background." >&2
  exit 1
fi

echo "Wrote $OUT (1024x1024, opaque)"
