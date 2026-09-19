#!/usr/bin/env python3
"""
Splits branding/tabs-icon.svg into the layers Icon Composer needs.

iOS 26 and later render app icons as layered artwork, applying the Liquid
Glass treatment and the light/dark/tinted/clear variants itself. Icon
Composer is a GUI app with no command line and an undocumented .icon format,
so the bundle has to be assembled by hand — but the layers it wants can be
exported here, which is the tedious part.

Layers are emitted back to front, matching the draw order in the source SVG
and the geometry recorded in branding/TAB_BAR_RECIPE.md:

    0-background   the radial field, opaque and full bleed
    1-tabs         the two inactive tabs stepping up and to the right
    2-page         the mint page and its two ghost rows
    3-active       the bloom and the active green tab, the focal element

Everything above the background keeps its alpha, so Icon Composer can
separate and parallax them.

    ./scripts/make-icon-layers.py          # writes branding/icon-layers/

Requires rsvg-convert (brew install librsvg).
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "branding" / "tabs-icon.svg"
OUT = ROOT / "branding" / "icon-layers"
SIZE = 1024

# Substrings identifying each element, in the order they appear in the source.
LAYERS = [
    ("0-background", ['<rect width="1024" height="1024" fill="url(#bg)">']),
    ("1-tabs",       ['x="690" y="252"', 'x="470" y="244"']),
    ("2-page",       ['x="152" y="360"', 'x="224" y="486"', 'x="224" y="576"']),
    ("3-active",     ['<circle cx="300"', 'x="152" y="232"']),
]


def main() -> int:
    if shutil.which("rsvg-convert") is None:
        sys.exit("error: rsvg-convert not found (brew install librsvg)")

    svg = SOURCE.read_text()
    defs = re.search(r"<defs>.*?</defs>", svg, re.S)
    assert defs, "no <defs> block in the source SVG"

    # Every drawable element on its own line, in document order.
    elements = re.findall(r"^\s*<(?:rect|circle)\b[^>]*></(?:rect|circle)>", svg, re.M)
    assert len(elements) == 8, f"expected 8 drawable elements, found {len(elements)}"

    OUT.mkdir(parents=True, exist_ok=True)
    used = 0
    for name, markers in LAYERS:
        picked = [e for e in elements if any(m in e for m in markers)]
        assert len(picked) == len(markers), \
            f"{name}: matched {len(picked)} elements, expected {len(markers)}"
        used += len(picked)

        body = "\n  ".join(picked)
        layer_svg = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" '
            f'width="{SIZE}" height="{SIZE}">\n  {defs.group(0)}\n  {body}\n</svg>\n'
        )
        svg_path = OUT / f"{name}.svg"
        png_path = OUT / f"{name}.png"
        svg_path.write_text(layer_svg)
        subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE),
                        "-o", str(png_path), str(svg_path)], check=True)
        print(f"  {png_path.relative_to(ROOT)}  ({len(picked)} element(s))")

    assert used == len(elements), f"{len(elements) - used} element(s) unassigned"
    print(f"\n{len(LAYERS)} layers in {OUT.relative_to(ROOT)}; all "
          f"{len(elements)} source elements accounted for.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
