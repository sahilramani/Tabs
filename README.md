<p align="center">
  <img src="docs/branding/logo-512.png" alt="Tabs" width="160" />
</p>

# Tabs

Keeps tabs on your subscriptions. A **privacy-first** iOS app that finds
recurring charges by scanning bank statements — **100% on-device**. Your
screenshots, PDFs, and financial data **never leave your phone**. There is no
networking layer in this app by design.

## How it works

1. **Import** a subscription either way:
   - **Scan Screenshot** — pick an image; Apple's **Vision** framework
     (`VNRecognizeTextRequest`) OCRs it locally.
   - **Import PDF Statement** — pick a PDF (or a folder of statements); **PDFKit**
     (`PDFDocument`) extracts the text locally.
2. **Detect** — a heuristic parser groups statement lines by merchant, clusters
   them by amount, and surfaces the ones that behave like subscriptions.
3. **Review** — a human-in-the-loop step. You edit the detected name, price, and
   cycle before anything is saved.
4. **Save** — selected items are written to a local **SwiftData** store and a
   local renewal reminder is scheduled via `UNUserNotificationCenter`.

Once saved, a subscription can be **cancelled** (kept for your records, dropped
from the spend total, reminders stopped) or **deleted** outright.

## Requirements

- Xcode 26+ (the design layer uses the iOS 26 `glassEffect` symbol; see the
  build note below)
- iOS 17.0+ at runtime

Open `Tabs.xcodeproj` and run on a device or simulator.

> Note: Vision OCR returns no text on a blank simulator photo library — test the
> screenshot path with a real statement image, or use the PDF path.

## Project structure

```
Tabs/
├── TabsApp.swift                      # App entry; local-only SwiftData container
├── Models/
│   ├── BillingCycle.swift             # Billing cadence, date math, cycle inference
│   ├── Subscription.swift             # SwiftData @Model (persistence, rollover, cancel state)
│   ├── ChargeRecord.swift             # Persisted statement evidence behind a subscription
│   ├── ScannedSubscriptionDraft.swift # Transient detection candidate
│   └── CurrencyFormat.swift           # Shared locale-aware currency formatting
├── Services/
│   ├── LocalStatementScannerService.swift  # Vision + PDFKit extraction
│   ├── RecurringChargeDetector.swift       # Recurring-charge heuristics
│   ├── SubscriptionKeywordCatalog.swift    # Modular brand registry (extend here)
│   └── NotificationManager.swift           # Local renewal reminders
├── Views/
│   ├── ContentView.swift              # Home: spend summary, active + cancelled lists
│   ├── ScanReviewView.swift           # Review/edit drafts, duplicate flags, save
│   ├── SubscriptionDetailView.swift   # Edit price/cycle/renewal; cancel/restore/delete
│   ├── AddSubscriptionView.swift      # Manual entry form
│   ├── PDFDocumentPicker.swift        # UIDocumentPickerViewController (PDFs + folders)
│   └── BrandStyle.swift               # Deterministic monogram avatars (no bundled logos)
├── DesignSystem/Theme.swift           # Semantic colors, type ramp, spacing, glass surface
└── PrivacyInfo.xcprivacy              # App Store privacy manifest
TabsTests/
└── RecurringChargeDetectorTests.swift # Detector, cycle-inference, and lifecycle tests
```

## Extending detection

Add brands in **one place** — `SubscriptionKeywordCatalog.defaultRules`:

```swift
BrandRule("Crunchyroll", aliases: ["crunchyroll", "crunchy roll"]),
```

The money-matching regex and detection heuristics (amount clustering, cadence
regularity, statement-vocabulary filtering) live in
`RecurringChargeDetector.swift`, with unit coverage in `TabsTests/`.

## Design system

The visual language ("Vital Green" accent, iOS 26 Liquid Glass) lives in
`Tabs/DesignSystem/Theme.swift` — semantic colors, an SF Pro type ramp,
spacing/radius scales, and the `tabsGlass()` surface — backed by named color
sets in `Assets.xcassets`.

> **Build note:** `tabsGlass()` uses `glassEffect` on iOS 26, so the project
> requires the **Xcode 26 SDK** to compile. It still runs on iOS 17+ via a
> `.regularMaterial` fallback.

## Privacy guarantees

- No `URLSession`, no analytics SDKs, no remote endpoints anywhere.
- SwiftData container is configured with `cloudKitDatabase: .none` (no iCloud sync).
- All OCR/PDF/parsing work runs locally and asynchronously off the main thread.
- `Tabs/PrivacyInfo.xcprivacy` declares it formally: no tracking, no
  collected data types, and required-reason entries only for APIs reached
  through Apple frameworks (SwiftData/CoreData, Foundation).
