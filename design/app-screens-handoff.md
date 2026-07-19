# Handoff: Tabs — iOS App Screens

## Overview
Four core screens of **Tabs**, a privacy-first, on-device subscription tracker for iOS (repo: `github.com/sahilramani/Tabs`): Home (spend summary + subscription list), Import sheet, Review detections, and Subscription detail. The designs follow Apple Design Resources / HIG conventions for iOS dark mode so they can be implemented almost entirely with system components.

## About the Design Files
The files in this bundle are **design references created in HTML** — they show intended look and behavior, they are not production code. The task is to **implement these screens in the Tabs codebase in SwiftUI** using standard system components (`NavigationStack`, `List(.insetGrouped)`, `.sheet` with detents, SF Symbols, system colors). Where a system component exists, prefer it over custom drawing — these mockups were designed to map 1:1 onto system UI.

## Fidelity
**High-fidelity.** Colors, typography, spacing, and copy are final. Match them pixel-perfectly *except* where a system default is the obvious equivalent (e.g. exact list-row insets, separator color, sheet corner radius on iOS 26) — in those cases the system default wins. Numbers below are in points at 393×852 (iPhone 16/17 class).

## Design Tokens
All colors are standard iOS dark-mode system colors — use the semantic Swift names, not hardcoded hex:

| Role | Hex (dark) | SwiftUI |
|---|---|---|
| App tint / accent | `#30D158` | `.green` (set as app `.tint`) |
| Background | `#000000` | `Color(.systemGroupedBackground)` |
| Card / row | `#1C1C1E` | `Color(.secondarySystemGroupedBackground)` |
| Label | `#FFFFFF` | `.primary` |
| Secondary label | `rgba(235,235,245,0.6)` | `.secondary` |
| Tertiary label | `rgba(235,235,245,0.3)` | `Color(.tertiaryLabel)` |
| Separator | `rgba(84,84,88,0.45)` | system default |
| Warning (cancel) | `#FFD60A` | `.yellow` |
| Destructive | `#FF453A` | `.red` |

Type: system SF Pro. Large title 34/700 · row title 17/600 · row value 17 `.secondary` · row subtitle 13 · section header 13/600 uppercase `.secondary` · spend figure 56/800 `.monospacedDigit` (cents at 35% opacity) · chips 12/600.
Shape: inset-grouped card radius 26 (iOS 26 default concentric radius — use system) · chips radius 7 · buttons capsule.
Avatars: **deterministic monograms, no bundled logos** — 40 pt circle (76 pt on detail), background = stable hue derived from name at ~18% opacity, letter = same hue full-strength, 17/600. Examples used: Netflix red, Spotify green, iCloud+ blue, Disney+ indigo, Notion orange, Hulu gray.

## Screens

### 01 — Home (`screenshots/home.png`)
- **Purpose**: total monthly spend + all subscriptions, sorted by soonest renewal.
- **Structure**: `NavigationStack` with large title **"Tabs"**; trailing gear button (`gearshape`, circular glass button — `.buttonStyle(.glass)` on iOS 26, plain toolbar item earlier).
- **Spend header** (not a list row): caption `MONTHLY SPEND` 13/600 uppercase secondary → `$84.97` 56/800 tabular (cents dimmed 35%) → `across 7 active subscriptions` 15/500 in tint green. Left-aligned, 20 pt margins.
- **ACTIVE section**: inset-grouped rows: monogram avatar 40 · name 17/600 + subtitle 13 (`Renews in 3 days` in **green** when ≤3 days, else secondary `Renews Jul 20`) · price 17/600 tabular · chevron. Rows: Netflix $15.49, Spotify $11.99, iCloud+ $2.99, Disney+ $13.99, Notion $8.00.
- **CANCELLED section**: same row at 55% opacity, price struck through, subtitle `Cancelled Jun 12`. (Hulu $17.99.)
- **Add button**: floating 60 pt circular Liquid Glass button, green-tinted, SF Symbol `plus`, bottom-trailing (20, 30). Opens Import sheet.

### 02 — Import sheet (`screenshots/import.png`)
- **Purpose**: choose how to feed Tabs a statement.
- **Presentation**: `.sheet` over Home, medium detent (~470 pt), grabber visible, system material background.
- **Header**: `Add subscriptions` 22/700 left; circular ✕ dismiss button (30 pt, `xmark`) right.
- **One grouped card, 4 rows** (icon circle 38 pt, green-tinted `rgba(48,209,88,0.16)` with green SF Symbol · title 16.5/600 · subtitle 13 secondary · chevron):
  1. `camera.viewfinder` — **Scan a screenshot** — "OCR your bank app, on-device"
  2. `doc.text` — **Import a PDF statement** — "Text extracted with PDFKit"
  3. `folder` — **Import a folder** — "Months at once — better detection"
  4. `pencil` — **Add manually** — "Name, price, and billing cycle"
- **Footer**: centered `lock` glyph + "Everything is read locally. Nothing leaves this iPhone." 12.5 tertiary.

### 03 — Review detections (`screenshots/review.png`)
- **Purpose**: confirm/edit detected candidates before saving.
- **Nav bar** (inline): `Cancel` (tint) · title `Review` 17/600 · **`Save 3`** 17/700 tint. Caption under bar, centered 13 secondary: `4 candidates · from 3 statements, Mar–Jun`.
- **Candidate cards** (grouped cells, 15–16 pt padding): header row = selection circle 26 pt (filled green + black check when selected; 2 pt gray ring when not) · name 17/600 · price 17/700 tabular. Chip row (indent 38): `Monthly`, `Next Jul 19` (gray chips, bg `rgba(118,118,128,0.24)`), `4 charges` (green chip).
- **Evidence box** (Netflix card): dark inset `#0D0D0E` radius 12, monospaced 10.5, one statement line per row: `05/15  NETFLIX.COM  CA` with amount right-aligned in green. Tappable per-card to expand.
- **States shown**: Adobe Creative Cloud = normal selected; Spotify = **duplicate**, yellow chip `Already tracked — will update`; Shell Oil = **deselected**, card at 55% opacity, gray chip `Amounts vary — looks one-off`.
- **Save button**: full-width capsule, 54 pt, green fill, black 17/700 label `Save 3 subscriptions`, pinned bottom (20 pt margins). Count updates with selection; disabled at 0.
- Name/price/cycle are editable in place (tap to edit).

### 04 — Subscription detail (`screenshots/detail.png`)
- **Purpose**: edit one subscription; cancel or delete it.
- **Nav bar** (inline): back `‹ Tabs` (tint) · `Edit` (tint).
- **Header**, centered: monogram 76 pt → name 28/700 → `$15.49 per month · $185.88 a year` 15 secondary → status capsule chip (green dot + `Active · renews in 3 days`, green text on `rgba(48,209,88,0.14)`).
- **Card 1** (label left 17, value right 17 secondary, chevron): Price `$15.49` · Billing cycle `Monthly` · Next renewal `Jul 19, 2026` · Reminder `3 days before`.
- **Card 2**: First detected `Mar 2026` (no chevron) · Matched charges `4` (chevron → evidence list).
- **Actions**: two separate single-row cards, centered 17/600: `Cancel Subscription` in yellow, `Delete Subscription` in red (red row should confirm via alert/confirmationDialog).
- **Footnote** centered 12.5 tertiary: "Cancelling keeps the history and stops the reminder. Everything stays on this iPhone."

## Interactions & Behavior
- Home row tap → Detail (push). `+` → Import sheet. Import option tap → system pickers (PhotosPicker / fileImporter), then push Review.
- Review: tap selection circle toggles card (animate opacity 1↔0.55, ~0.2 s); Save dismisses to Home with new rows.
- Detail: Cancel → row moves to CANCELLED section, spend total drops, reminder unscheduled; fully reversible (Restore replaces Cancel when viewing a cancelled sub). Delete → confirmation, permanent.
- Renewal subtitle turns green (and sorts to top) when renewal ≤3 days away.
- Liquid Glass (`.glass` button styles, floating controls) on iOS 26+; fall back to `.ultraThinMaterial` / standard toolbar buttons on iOS 17–18.
- All processing on-device; no networking anywhere.

## State Management
- `subscriptions: [Subscription]` (name, price, cycle, nextRenewal, reminderOffset, status active/cancelled, matchedCharges, firstDetected) — persisted locally (SwiftData/Core Data, CloudKit **disabled**).
- Derived: `monthlySpend` (every cycle normalized to monthly — $120/yr → $10/mo), `activeCount`, sort by `nextRenewal`.
- Review flow: `candidates: [DetectionCandidate]` (editable fields + `isSelected` + `isDuplicate` + evidence lines) — transient until saved.
- Reminders via `UNUserNotificationCenter`, scheduled/cancelled with status changes.

## Assets
No image assets required. All icons are SF Symbols; avatars are generated monograms. Status bar, grabber, and home indicator in the PNGs are system chrome — do not implement.

## Files
- `Tabs App Screens.dc.html` — interactive HTML reference, all 4 screens side by side (open in a browser; `support.js` must sit next to it).
- `screenshots/home.png · import.png · review.png · detail.png` — 786×1704 (2×) captures, also used on the docs Usage page.
