# App Screens Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the four screens from the `Tabs.zip` design handoff (Home, Import sheet, Review detections, Subscription detail) in SwiftUI, preserving all existing functionality (Trash, About, reminders banner, drag-drop, scanning overlay).

**Architecture:** Redesign the three existing screens (`ContentView`, `ScanReviewView`, `SubscriptionDetailView`) in place and add one new `ImportSheetView`. Small model/service extensions first (per-subscription reminder offset, detector near-miss candidates, scanner statement metadata), each TDD'd, then the view layer. Liquid Glass on iOS 26 via the existing `#if compiler(>=6.2)` gating pattern; iOS 17 fallbacks throughout.

**Tech Stack:** SwiftUI, SwiftData, XCTest, Vision/PDFKit (untouched), UNUserNotificationCenter. Xcode 26.6, deployment target iOS 17.

**Branch:** `feature/app-screens-redesign` off `main`. Commit after each task.

**Status:** Shipped — squash-merged to `main` as #12 on 2026-07-16; the branch is deleted. Kept as a record of how the redesign was scoped.

**Design references:** `design/` — `app-screens-handoff.md` + `design/screenshots/` (home.png, import.png, review.png, detail.png). Colors are existing `Theme` tokens (AccentPrimary dark = #30D158 already matches the handoff).

---

### Task 0: Branch

- [x] `git -C /Users/sahilramani/dev/Tabs checkout -b feature/app-screens-redesign`

### Task 1: Per-subscription reminder offset

The detail screen's "Reminder — 3 days before" row needs a persisted, per-subscription lead time. `NotificationManager` has a global `leadTimeDays = 3`; move it onto the model.

**Files:**
- Modify: `Tabs/Models/Subscription.swift`
- Modify: `Tabs/Services/NotificationManager.swift`
- Test: `TabsTests/SubscriptionReminderTests.swift` (create)

- [x] **Step 1: Write failing tests**

```swift
//
//  SubscriptionReminderTests.swift
//  TabsTests
//
//  Reminder lead-time: the persisted per-subscription offset and the pure
//  fire-date math used by NotificationManager.
//

import XCTest
@testable import Tabs

final class SubscriptionReminderTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return Calendar.current.date(from: components)!
    }

    func testReminderDaysBeforeDefaultsToThree() {
        let sub = Subscription(name: "Netflix", price: 15.49, billingCycle: .monthly, renewalDate: .now)
        XCTAssertEqual(sub.reminderDaysBefore, 3)
    }

    func testFireDateIsLeadDaysBeforeRenewal() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 1)
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 3, now: now)
        XCTAssertEqual(Calendar.current.startOfDay(for: fire),
                       Calendar.current.startOfDay(for: date(2026, 7, 16)))
    }

    func testFireDateNeverInThePast() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 18)   // 3 days before is already gone
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 3, now: now)
        XCTAssertGreaterThan(fire, now)
    }

    func testZeroDaysMeansRenewalDay() {
        let renewal = date(2026, 7, 19)
        let now = date(2026, 7, 1)
        let fire = NotificationManager.fireDate(for: renewal, daysBefore: 0, now: now)
        XCTAssertEqual(Calendar.current.startOfDay(for: fire),
                       Calendar.current.startOfDay(for: renewal))
    }
}
```

- [x] **Step 2: Run tests, verify they fail** (`reminderDaysBefore`/`fireDate` don't exist — build error is the failure)
- [x] **Step 3: Implement**

`Subscription.swift` — add stored property after `deletedAt` + init param (default keeps SwiftData migration clean):

```swift
    /// How many days before `renewalDate` the local reminder fires. Persisted
    /// per subscription so each one can have its own lead time; defaults to 3
    /// (the previous app-wide behavior) so existing stores migrate unchanged.
    var reminderDaysBefore: Int = 3
```

`NotificationManager.swift` — replace `var leadTimeDays: Int = 3` with a pure static helper, and use the subscription's own offset:

```swift
    /// The moment a reminder should fire: `daysBefore` days ahead of the
    /// renewal, clamped so it's never in the past. Pure and unit-tested.
    static func fireDate(for renewalDate: Date, daysBefore: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let target = calendar.date(byAdding: .day, value: -daysBefore, to: renewalDate) ?? renewalDate
        return max(target, now.addingTimeInterval(5))
    }
```

In `scheduleRenewalReminder`, replace the fireDate block with:

```swift
        let triggerDate = Self.fireDate(for: subscription.renewalDate, daysBefore: subscription.reminderDaysBefore)
```

- [x] **Step 4: Run tests, verify pass**
- [x] **Step 5: Commit** `feat: per-subscription reminder lead time`

### Task 2: Detector emits "amounts vary" near-miss candidates

Review screen shows Shell Oil as a deselected card with a gray "Amounts vary — looks one-off" chip. Today the detector silently drops unknown merchants whose amounts vary. Emit clusters that pass every leg *except* amount stability (≥3 charges on ≥3 days, regular gaps, known cadence) as deselected drafts with a new `amountsVary` flag.

**Files:**
- Modify: `Tabs/Models/ScannedSubscriptionDraft.swift`
- Modify: `Tabs/Services/RecurringChargeDetector.swift`
- Test: `TabsTests/RecurringChargeDetectorTests.swift`

- [x] **Step 1: Failing tests** (append to existing XCTestCase)

```swift
    // MARK: - Amounts-vary near misses

    func testVaryingAmountsWithRegularCadenceEmitDeselectedCandidate() {
        let text = """
        03/15 SHELL OIL 5744 MOUNTAIN VIEW $38.10
        04/15 SHELL OIL 5744 MOUNTAIN VIEW $51.72
        05/15 SHELL OIL 5744 MOUNTAIN VIEW $42.13
        """
        let drafts = detector.drafts(from: text)
        let shell = drafts.first { $0.name.localizedCaseInsensitiveContains("shell") }
        XCTAssertNotNil(shell)
        XCTAssertEqual(shell?.amountsVary, true)
        XCTAssertEqual(shell?.isSelected, false)
    }

    func testIrregularSpendingIsStillDropped() {
        // Varying amounts AND irregular gaps — ordinary shopping, not a candidate.
        let text = """
        03/02 SOME BODEGA NYC $12.10
        03/05 SOME BODEGA NYC $31.72
        03/21 SOME BODEGA NYC $4.13
        """
        let drafts = detector.drafts(from: text)
        XCTAssertFalse(drafts.contains { $0.name.localizedCaseInsensitiveContains("bodega") })
    }

    func testStableAmountsAreNotFlagged() {
        let text = """
        03/05 SPOTIFY USA $11.99
        04/05 SPOTIFY USA $11.99
        05/05 SPOTIFY USA $11.99
        """
        let drafts = detector.drafts(from: text)
        let spotify = drafts.first { $0.name.localizedCaseInsensitiveContains("spotify") }
        XCTAssertEqual(spotify?.amountsVary, false)
        XCTAssertEqual(spotify?.isSelected, true)
    }
```

- [x] **Step 2: Run, verify fail**
- [x] **Step 3: Implement**

`ScannedSubscriptionDraft.swift` — add after `isAlreadyTracked`:

```swift
    /// Set by the detector when this merchant recurs on a regular cadence but
    /// with varying amounts (gas stations, restaurants) — probably not a
    /// subscription, surfaced deselected so the user makes the call.
    var amountsVary: Bool = false
```

(plus `amountsVary: Bool = false` init param assigning it, keeping the memberwise call sites source-compatible.)

`RecurringChargeDetector.swift`:
- Extract the amount-stability check from `isLikelySubscription` into `private static func amountsAreStable(_ amounts: [Decimal]) -> Bool`.
- Add `private func isRecurringButVarying(_ cluster: [Charge]) -> Bool`: unknown/unhinted cluster, ≥3 charges on ≥3 distinct days, `!amountsAreStable`, `inferredCycle != nil`, `gapsAreRegular`.
- In `drafts(from:)`'s cluster loop, when `isLikelySubscription` fails but `isRecurringButVarying` passes, build the draft with `isSelected: false, amountsVary: true`.

- [x] **Step 4: Run all detector tests, verify pass**
- [x] **Step 5: Commit** `feat: surface recurring-but-varying charges as deselected candidates`

### Task 3: Scanner reports statement count (ScanBatch)

Review caption: "4 candidates · from 3 statements, Mar–Jun". Scanner must report how many sources fed the scan.

**Files:**
- Modify: `Tabs/Services/LocalStatementScannerService.swift`
- Modify: `Tabs/Views/ContentView.swift` (call sites + DraftsBox)
- Test: none (I/O plumbing; covered by build + e2e)

- [x] **Step 1: Implement**

`LocalStatementScannerService.swift` — add above the service:

```swift
/// What one scan produced: the detected drafts plus how many source documents
/// (screenshots / PDF statements) actually contributed text.
struct ScanBatch {
    let drafts: [ScannedSubscriptionDraft]
    let statementCount: Int
    /// Singular noun for the caption, e.g. "screenshot" or "statement".
    let sourceNoun: String
}
```

- `scanImage` returns `ScanBatch(drafts: ..., statementCount: 1, sourceNoun: "screenshot")`.
- `scanPDFs` returns `ScanBatch(drafts: ..., statementCount: readCount, sourceNoun: "statement")`.
- `scanPDF` keeps forwarding to `scanPDFs`.

`ContentView.swift` — `runScan`'s `work` closure returns `ScanBatch`; `DraftsBox` gains `let batch: ScanBatch`-style fields (drafts, statementCount, sourceNoun); `--seed-review` builds `DraftsBox(drafts: demo, statementCount: 3, sourceNoun: "statement", source: "bank statements")`. `ScanReviewView` init gains `statementCount`/`sourceNoun` (Task 6 consumes them).

- [x] **Step 2: Build, verify compiles + all tests pass**
- [x] **Step 3: Commit** `feat: scanner reports how many statements fed a scan`

### Task 4: Review caption + date-window helper (TDD)

**Files:**
- Create: `Tabs/Models/ReviewCaption.swift`
- Test: `TabsTests/ReviewCaptionTests.swift` (create)

- [x] **Step 1: Failing tests**

```swift
import XCTest
@testable import Tabs

final class ReviewCaptionTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testCaptionWithWindow() {
        let caption = ReviewCaption.text(
            candidateCount: 4, statementCount: 3, sourceNoun: "statement",
            chargeDates: [date(2026, 3, 15), date(2026, 6, 15), date(2026, 4, 2)]
        )
        XCTAssertEqual(caption, "4 candidates · from 3 statements, Mar–Jun")
    }

    func testSingularEverything() {
        let caption = ReviewCaption.text(
            candidateCount: 1, statementCount: 1, sourceNoun: "screenshot",
            chargeDates: [date(2026, 3, 2)]
        )
        XCTAssertEqual(caption, "1 candidate · from 1 screenshot, Mar")
    }

    func testNoDatesOmitsWindow() {
        let caption = ReviewCaption.text(
            candidateCount: 2, statementCount: 1, sourceNoun: "statement", chargeDates: []
        )
        XCTAssertEqual(caption, "2 candidates · from 1 statement")
    }

    func testCrossYearWindowKeepsYears() {
        let caption = ReviewCaption.text(
            candidateCount: 2, statementCount: 4, sourceNoun: "statement",
            chargeDates: [date(2025, 11, 3), date(2026, 2, 11)]
        )
        XCTAssertEqual(caption, "2 candidates · from 4 statements, Nov 2025–Feb 2026")
    }
}
```

- [x] **Step 2: Run, verify fail**
- [x] **Step 3: Implement `ReviewCaption.text(candidateCount:statementCount:sourceNoun:chargeDates:calendar:)`** — pure string builder: pluralize "candidate"/noun with a trailing "s"; window from min/max charge dates, abbreviated month names, en dash, same-month collapses to one label, different years append the year to both ends.
- [x] **Step 4: Run, verify pass**
- [x] **Step 5: Commit** `feat: review-screen caption builder`

### Task 5: Home screen redesign

**Files:**
- Modify: `Tabs/Views/ContentView.swift`
- Modify: `Tabs/DesignSystem/Theme.swift` (spend-figure font + chip tokens if needed)

Changes (per home.png):
- Replace `SpendSummaryCard` with a left-aligned plain header: `MONTHLY SPEND` caption (13/600 uppercase, secondary) → dollars 56/heavy monospacedDigit with cents (incl. separator) at 35% opacity → `across N active subscriptions` (15/500, accent). 20pt leading margin, clear list row.
- Sections renamed `Active` / `Cancelled`. Row: avatar 40, name 17/600, subtitle 13 (`Renews in N days` in accent when ≤3 days; `Renews today` accent; else `Renews Jul 20` secondary; cancelled: `Cancelled Jun 12` tertiary). Price 17/600 tabular, struck-through + 55% row opacity when cancelled; cycle suffix shown only when non-monthly.
- Toolbar: keep StageBadge + conditional Trash; replace info button with trailing `gearshape` → About sheet.
- Delete `importBar`; floating 60pt circular accent `plus` button bottom-trailing (20, 30) → Import sheet. `.glassEffect`/`.glassProminent` on iOS 26 via `#if compiler(>=6.2)`, `Circle().fill(Theme.accent)` + shadow fallback. `.contentMargins(.bottom, 88, for: .scrollContent)` so the list clears it.
- Empty state action opens the import sheet.
- Import flow state: `isShowingImportSheet`, `pendingImportAction: ImportAction?`, `.photosPicker(isPresented:selection:)`, `isShowingPDFPicker`, `isShowingFolderPicker`. Sheet `onDismiss` fires the pending action (Task 7 wires the sheet itself; this task can land with the button presenting a placeholder `ImportSheetView()` if Task 7 is done first — do Task 7 before this if executing out of order; otherwise land both before building).
- Keep: drag-drop, scanning overlay, error alert, reminders banner, `--seed-review`/`--seed-demo`, swipe actions, rollOverdueRenewals.

- [x] **Step 1: Implement** (full code in-task during execution; this is a view-layer task verified by build + screenshot)
- [x] **Step 2: Build for iOS Simulator, verify compiles; run unit tests**
- [x] **Step 3: Commit** `feat: redesigned home screen (spend header, active/cancelled sections, floating add)`

### Task 6: Import sheet (new view)

**Files:**
- Create: `Tabs/Views/ImportSheetView.swift`
- Modify: `Tabs/Views/PDFDocumentPicker.swift` (add `contentTypes` parameter, default `[.pdf, .folder]`)
- Modify: `Tabs/Views/ContentView.swift` (present + handle actions)

Per import.png:
- `.sheet` medium-ish detent (`.height(470)` + `.medium` fallback), `presentationDragIndicator(.visible)`.
- Header: `Add subscriptions` 22/700 leading; trailing 30pt circular `xmark` dismiss.
- One grouped card, 4 rows (38pt icon circle, accent at 16% fill + accent symbol; title 16.5/600; subtitle 13 secondary; chevron):
  1. `camera.viewfinder` Scan a screenshot — "OCR your bank app, on-device"
  2. `doc.text` Import a PDF statement — "Text extracted with PDFKit"
  3. `folder` Import a folder — "Months at once — better detection"
  4. `pencil` Add manually — "Name, price, and billing cycle"
- Footer: `lock` + "Everything is read locally. Nothing leaves this iPhone." 12.5 tertiary, centered.
- Emits `ImportAction` enum (`scanScreenshot`, `importPDF`, `importFolder`, `addManually`) via closure; row tap sets action + dismisses; ContentView's `onDismiss` presents the matching picker (photosPicker / PDF picker `[.pdf]` / folder picker `[.folder]`, Catalyst folder → `chooseFoldersViaOpenPanel`) or the manual-add sheet.

- [x] **Step 1: Implement**
- [x] **Step 2: Build + tests pass**
- [x] **Step 3: Commit** `feat: import sheet with four on-device import paths`

### Task 7: Review screen redesign

**Files:**
- Modify: `Tabs/Views/ScanReviewView.swift`

Per review.png:
- Inline nav: `Cancel` / title `Review` / trailing `Save N` (17/700). Caption row under the bar (13 secondary, centered) from `ReviewCaption.text(...)` using all drafts' transaction dates.
- Candidate cards (inset-grouped cells): header row = 26pt selection circle (accent fill + black `checkmark` when selected; 2pt `Theme.tertiary` ring when not) · name TextField 17/600 · price TextField 17/700 tabular trailing. Card at 55% opacity when deselected (0.2s animation).
- Chip row (indent 38): cycle chip as Menu picker (gray chip, `Color(.tertiarySystemFill)`-equivalent `Theme` fill), `Next Jul 19` gray chip, `N charges` accent chip (only when transactions exist; tap toggles evidence box), yellow chip `Already tracked — will update` when `isAlreadyTracked`, gray chip `Amounts vary — looks one-off` when `amountsVary`. Chips 12/600, radius 7.
- Evidence box (expanded state, default-collapsed): near-black inset (`Color.black.opacity(0.35)` over the card, radius 12), monospaced ~10.5, one line per transaction: `MM/dd` + merchant text + trailing amount in accent.
- `markAlreadyTrackedDrafts`: keep flagging, **stop deselecting** (design counts duplicates in Save; save already updates in place).
- Bottom pinned save: full-width 54pt capsule, accent fill, black 17/700 label `Save N subscription(s)`, disabled at 0, 20pt margins. Keep existing save/plan logic untouched.
- Empty state unchanged.

- [x] **Step 1: Implement**
- [x] **Step 2: Build + all tests pass (existing plan/dedupe tests must stay green)**
- [x] **Step 3: Commit** `feat: redesigned review screen (cards, chips, evidence, pinned save)`

### Task 8: Detail screen redesign

**Files:**
- Modify: `Tabs/Views/SubscriptionDetailView.swift`
- Modify: `Tabs/Models/BillingCycle.swift` (add `perLabel`: "per week/month/quarter/year")

Per detail.png:
- Inline nav, trailing `Edit` → rename alert with TextField.
- Header (clear list section, centered): avatar 76 → name 28/700 → `$15.49 per month · $185.88 a year` (15, secondary; yearly-equivalent = monthlyEquivalent×12; for `.yearly` show `≈ $X a month` instead) → status capsule: active = accent dot + `Active · renews in N days`/`renews Jul 19` on accent 14% fill; cancelled = tertiary dot + `Cancelled Jun 12` on tertiary fill.
- Card 1 (LabeledContent-style rows): Price (tap → alert with decimal TextField) · Billing cycle (Menu picker, keeps `realignRenewal` binding) · Next renewal (compact DatePicker, keeps `startOfDay...` range) · Reminder (Menu: On renewal day / 1 / 2 / 3 / 5 / 7 days before → writes `reminderDaysBefore`).
- Card 2 (only when charges exist): First detected `Mar 2026` (earliest charge date, no chevron) · Matched charges `N` → push `ChargesListView` (new inner view in same file: list of date + raw line + amount rows). Manual subs: single row `Added` + created month.
- Actions: separate single-row cards, centered 17/600 — `Cancel Subscription` (Theme.warning) when active / `Restore Subscription` (accent) when cancelled; `Delete Subscription` (Theme.destructive) → `confirmationDialog` ("This moves it to the Trash — you can restore it from there.") → existing `moveToTrash()`.
- Footnote centered 12.5 tertiary: "Cancelling keeps the history and stops the reminder. Everything stays on this iPhone." + provenance line below.
- Keep: `BillingSnapshot` reschedule-on-exit logic (extend snapshot with `reminderDaysBefore`), cancel/restore/trash flows, `NotificationManager` calls.

- [x] **Step 1: Implement**
- [x] **Step 2: Build + tests**
- [x] **Step 3: Commit** `feat: redesigned subscription detail (header, editable rows, reminder, evidence)`

### Task 9: Demo seed parity + CHANGELOG

**Files:**
- Modify: `Tabs/TabsApp.swift` (`--seed-demo`: add Disney+ $13.99, Notion $8.00, Hulu cancelled $17.99 so home.png matches)
- Modify: `Tabs/Views/ContentView.swift` (`--seed-review` demo drafts: Netflix 4 charges, Adobe Creative Cloud $22.99 3 charges, Spotify duplicate, Shell Oil amountsVary — mirroring review.png)
- Modify: `CHANGELOG.md` (Unreleased → Changed: the four redesigned screens; Added: per-subscription reminder lead time, amounts-vary candidates)

- [x] **Step 1: Implement, build, tests**
- [x] **Step 2: Commit** `chore: demo seeds mirror design handoff; changelog`

### Task 10: End-to-end verification

- [x] Build: `xcodebuild -project Tabs.xcodeproj -scheme Tabs -destination 'platform=iOS Simulator,name=<newest iPhone>' build`
- [x] Tests: `xcodebuild test` same destination — all green
- [x] Boot simulator (dark mode), launch with `--seed-demo`, screenshot home; launch with `--seed-review`, screenshot review; navigate detail + import sheet via simctl/UI where feasible; compare against `screenshots/*.png`
- [x] Fix discrepancies, re-screenshot
- [x] Final commit

## Self-Review

- Spec coverage: Home ✓ (T5), Import ✓ (T6), Review ✓ (T4+T7), Detail ✓ (T1+T8), tokens (existing Theme ✓), interactions ✓ (T5–T8), state mgmt ✓ (T1–T3), reminder offset ✓ (T1), duplicate-selected behavior ✓ (T7), amounts-vary ✓ (T2), caption ✓ (T3+T4). Deviations (kept features): trash-not-permanent-delete, gear→About, StageBadge/Trash toolbar items kept, price suffix on non-monthly rows.
- Placeholders: view tasks carry exact specs (fonts/sizes/colors/copy) rather than full Swift blocks; the executing session is this session with full context + design PNGs on disk.
- Type consistency: `ScanBatch(drafts:statementCount:sourceNoun:)` (T3) consumed by `ReviewCaption.text` (T4) and `ScanReviewView` (T7); `reminderDaysBefore` (T1) consumed by T8; `amountsVary` (T2) consumed by T7.
