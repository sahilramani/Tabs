#!/usr/bin/env bash
#
# Renders statement.html to a text-selectable PDF for demoing Tabs's PDF
# import. Uses headless Chrome so the output has real extractable text (not a
# scanned image), which is what PDFKit reads.
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$DIR/sample-statement.pdf" "$DIR/statement.html"

echo "Wrote $DIR/sample-statement.pdf"
