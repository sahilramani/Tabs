# Tab Bar — geometry recipe for `scripts/make_icon.swift`

Shipped concept (round 5). All values in unit coordinates (`u = side / 1024`).
The SVG reference (`tabs-icon-tab-bar.svg`, this folder) is y-down; your
NSGraphicsContext is y-up — flip y as `yCG = 1024 − ySVG − height`. The page
stays inside the frame (no bleed). All shapes are rounded rects — no rotations,
no paths.

Nine primitives: field, two inactive tabs, page, bloom, active tab, two rows.

## Palette

| role | hex | existing constant |
|---|---|---|
| active tab top sheen | `#D9FFE4` | `mintGlow` |
| active tab body | `#30D158` | `vitalGreen` |
| active tab base | `#1FA64C` | — |
| page top / bottom | `#EBF9F0` / `#CDE6D5` | — (mint page) |
| charcoal tab top / bottom | `#27292B` / `#0F1011` | — |
| dark tab top / bottom | `#16251B` / `#0A130E` | — |
| field center / edge | `#17291F` / `#050806` | `bgCenter` / `bgEdge` |

## Draw order (back to front)

1. **Field** — radial gradient, center `(0.38w, 0.30h)` (y-down; mirror for
   CG), radius `0.95w`: `bgCenter → bgEdge`.
2. **Back inactive tab** — rounded rect `220×160 u`, corner `38 u`, at SVG
   `(690, 252)`. Dark-tab vertical gradient; stroke black @ 0.20 α, `3 u`.
   (Dimmest + smallest — it sits furthest back, top-right.)
3. **Middle inactive tab** — `250×168 u`, corner `40 u`, at `(470, 244)`.
   Charcoal gradient; stroke black @ 0.18 α. Slightly larger/brighter than the
   back tab so the row reads as receding depth.
4. **Page** — `720×528 u`, corner `52 u`, at `(152, 360)`. Mint page gradient;
   stroke black @ 0.08 α. Covers the bottom of both inactive tabs so they read
   attached to the bar.
5. **Bloom** — radial at SVG `(300, 430)`, radius `0.293w` (300 u):
   `vitalGreen @ 0.50 α → 0.16 α (offset 0.55) → 0 α`.
6. **Active tab** — `312×184 u`, corner `42 u`, at `(152, 232)`. Fill: vertical
   gradient `#D9FFE4 → #30D158 (offset 0.32) → #1FA64C`. Stroke: mint
   `#D9FFE4` @ 0.50 α, `3 u`. Left-aligned with the page; its bottom (y416)
   overlaps the page top (y360) by 56 u so it reads as the front/active tab
   fused to the content area. Optional 1024-only flourish: double-fill green
   shadow at blur `0.08w`.
7. **Ghost rows** — `430×40 u` r20 at `(224, 486)`, dark `rgb(18,40,26)` @
   0.13 α; `300×40 u` r20 at `(224, 576)`, same color @ 0.08 α.

The active tab is left-aligned (x152) so the "active = frontmost, leftmost" tab
metaphor holds; the inactive tabs step up-and-right (x470, x690) and sit higher
(y244, y252) to fake perspective depth.

## Small sizes

Verified at 120 / 60 / 29 px in the artifact — the white page + green tab value
break keeps it legible as a window-with-a-tab, never a dot. If 29 px muddies:
drop the back inactive tab and the ghost rows; keep field, middle tab, page,
active tab.

## Safe zone

Mark extent: x 152–910, y 232–888 — inside the outer-8% safe zone on all sides.
