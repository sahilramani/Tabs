# Changelog

All notable changes to Tabs are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While Tabs is pre-1.0 it ships as an **alpha**: the data model and detection
heuristics may still change between releases.

## [Unreleased]

### Changed
- New app icon — a browser-tab-bar mark with the active tab in Vital Green,
  rendered from `branding/tabs-icon.svg` via `scripts/make-icon.sh`. The README
  logo is regenerated from the same source to match.

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

[Unreleased]: https://github.com/sahilramani/Tabs/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sahilramani/Tabs/releases/tag/v0.1.0
