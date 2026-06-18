#!/usr/bin/env bash
#
# Renders branding/social-card.html to docs/branding/social-1280x640.png — the
# site's social / OpenGraph preview image. Uses headless Chrome so the gradient
# theme and the tab-bar mark render exactly as on the landing page.
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$DIR/docs/branding/social-1280x640.png"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1280,640 --screenshot="$OUT" "file://$DIR/branding/social-card.html"

echo "Wrote $OUT (1280x640)"
