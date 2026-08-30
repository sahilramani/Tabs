# Changelog

All notable changes to Tabs are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While Tabs is pre-1.0 it ships as an **alpha**: the data model and detection
heuristics may still change between releases.

## [Unreleased]

Nothing yet.

## [0.3.0] - 2026-08-30

### Added
- Sample statements ship with the app — four fictional months from a bank that
  doesn't exist, readable in full before importing, so the detector can be
  tried without handing it a real bank statement. Four months because
  detection needs three sightings of a charge before it will call something
  recurring; a single statement finds nothing.
- A privacy policy page at <https://www.sahilramani.com/Tabs/privacy.html>,
  generated from `PRIVACY.md` so the hosted policy and the one in the
  repository cannot drift apart. CI fails if they do.

### Changed
- Scoped to iPhone. iPad and Mac Catalyst are off until those layouts actually
  exist, rather than shipping a stretched phone layout as tablet support.
- Locked to portrait. Every screen was designed and captured portrait, and
  rotating only stretched them.
- Signed builds read the Apple Developer Team ID from `ASC_TEAM_ID` instead of
  carrying it in the committed project, so contributors aren't pushed onto a
  team they don't belong to. `make device`, `make archive`, and `make export`
  now fail with a readable message when it isn't set.
- `samples/` generates the whole four-month set; the single-month fixture it
  replaces could not produce a detection at all.

### Fixed
- Social share cards. `og:image` pointed at the `github.io` address, which only
  redirects to the site's real domain, and scrapers generally don't follow
  redirects for images.
- The site now enforces HTTPS. The custom domain had an approved certificate,
  but enforcement was off, so `http://` was answered as-is.

## [0.2.0] - 2026-08-19

### Added
- Per-subscription reminder lead time — each subscription now has its own
  "Reminder" setting (on renewal day up to 7 days before) on the detail screen.
- The detector now surfaces merchants that recur on a regular cadence but with
  varying amounts (gas stations, utilities) as deselected review candidates
  badged "Amounts vary — looks one-off", instead of hiding them.
- Import sheet: the floating add button opens a single sheet with all four
  paths — scan a screenshot, import a PDF statement, import a folder, or add
  manually.

### Changed
- Redesigned all four core screens per the app-screens design handoff:
  - **Home** — plain left-aligned monthly-spend header with dimmed cents,
    Active/Cancelled sections, renewal subtitles that turn green inside the
    3-day window, a gear button for About, and a floating Liquid Glass add
    button (replaces the bottom import bar).
  - **Review** — one card per candidate with a selection circle, editable name
    and price, cycle/renewal/charge-count chips, an expandable
    statement-evidence box, an "Already tracked — will update" badge (duplicates
    now stay selected and update in place), and a pinned "Save N subscriptions"
    capsule. The caption reports candidates, statements, and the month window.
  - **Detail** — centered monogram header with a status capsule, tappable
    Price/Billing cycle/Next renewal/Reminder rows, First detected + Matched
    charges provenance card, and centered Cancel/Restore and Delete rows
    (Delete confirms, then moves to the Trash).
- New app icon — a browser-tab-bar mark with the active tab in Vital Green,
  rendered from `branding/tabs-icon.svg` via `scripts/make-icon.sh`. The README
  logo is regenerated from the same source to match.
- Redesigned the GitHub Pages landing (`docs/index.html`) — dark on-brand
  marketing page with hero, how-it-works, features, privacy, and FAQ.

### Fixed
- Changing the billing cycle in the scan review screen now recomputes the
  renewal date, so a draft saved as yearly no longer keeps a monthly renewal.

## [0.1.0] - 2026-06-14

First alpha.

### Added
- On-device statement import: scan a screenshot (Vision OCR) or import a PDF /
  folder of PDFs (PDFKit). Nothing leaves the device.
- Recurring-charge detection that groups statement lines by merchant, splits a
  merchant into price clusters, and surfaces likely subscriptions.
- Review screen: edit a draft's name, price, and billing cycle before saving;
  inspect the statement lines behind each detection.
- Duplicate guard on import — a draft is matched to an existing subscription by
  brand and price, so re-importing updates in place instead of duplicating, and
  distinct same-brand plans stay separate.
- Local persistence (SwiftData) and renewal reminders (local notifications).
- Subscription lifecycle: cancel/restore (kept in an archive), and a **trash**
  with restore and empty — deletes are undoable.
- Editing the billing cycle realigns the next renewal date to the new cadence.
- Multi-currency display (USD, EUR, GBP detected from statement symbols).
- Monthly-equivalent spend summary across active subscriptions.

### Security & privacy
- No networking layer, no analytics, no tracking. iCloud sync disabled.
- App Store privacy manifest declares no data collection.

[Unreleased]: https://github.com/sahilramani/Tabs/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/sahilramani/Tabs/releases/tag/v0.3.0
[0.2.0]: https://github.com/sahilramani/Tabs/releases/tag/v0.2.0
[0.1.0]: https://github.com/sahilramani/Tabs/releases/tag/v0.1.0
