---
name: verify
description: Build, run, and visually verify the Tabs iOS app in the Simulator — launch seeded demo data, capture screenshots, drive the UI.
---

# Verifying Tabs

Surface is an iOS GUI: build for the simulator, launch with seed args, screenshot, and drive taps via computer-use on the Simulator window.

## Build + install + launch

```bash
# Build (Xcode 26 toolchain; scheme "Tabs"; iPhone 17 Pro / iOS 26.5 sim exists)
xcodebuild -project Tabs.xcodeproj -scheme Tabs -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build/DerivedData build -quiet

UD=$(xcrun simctl list devices | grep "iPhone 17 Pro (" | grep -o "[0-9A-F-]\{36\}" | head -1)
xcrun simctl boot $UD 2>/dev/null; xcrun simctl ui $UD appearance dark
xcrun simctl install $UD build/DerivedData/Build/Products/Debug-iphonesimulator/Tabs.app
xcrun simctl launch $UD com.sahilramani.tabs --seed-demo      # bundle id is lowercase "tabs"
xcrun simctl io $UD screenshot out.png
```

## Gotchas

- Bundle id is `com.sahilramani.tabs` (lowercase t) — `com.sahilramani.Tabs` fails with FBSOpenApplicationServiceErrorDomain 4.
- `--seed-demo` only seeds an **empty** store; `simctl uninstall` first for a clean slate.
- `--seed-review` presents the review sheet with demo drafts (add `--seed-demo` too if you want duplicates flagged). DEBUG builds only.
- Design reference screenshots live in the app-screens handoff bundle (originally `~/Downloads/Tabs.zip` → `design_handoff_app_screens/screenshots/`).
- Mouse-wheel scroll does nothing in the Simulator — use a click-drag to scroll lists.
- Saving from the review sheet triggers the notification-permission alert on first run; Allow it or reminders silently no-op.

## Flows worth driving

- Home: spend header math (active only), ≤3-day renewals green, Cancelled section dimmed/struck.
- `+` → import sheet → each row routes to its picker **after** the sheet dismisses (`performPendingImportAction`).
- Review: selection circle toggles update both Save counts; charges chip expands the evidence box; duplicates stay selected and update in place on save (spend total changes, no duplicate rows).
- Detail: Reminder menu persists per subscription; Cancel moves the row to Cancelled and drops the spend total; Delete confirms then moves to Trash (trash toolbar icon appears on Home).
