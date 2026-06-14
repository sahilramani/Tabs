# Contributing to Tabs

Thanks for working on Tabs. This doc covers how we ship changes and the rules
that keep the project honest.

## The one rule that matters

Tabs is privacy-first and **100% on-device**. There is no networking layer, and
that is a feature, not an oversight.

Do not add:

- `URLSession`, sockets, or any remote endpoint
- Analytics, crash reporting, or telemetry SDKs
- iCloud / CloudKit sync (the SwiftData container is `cloudKitDatabase: .none`)
- Anything that reads a user's statement data off the device

A PR that breaks this gets closed regardless of how good the rest of it is. If
you think a change genuinely needs the network, open an issue first and make the
case before writing code.

## Getting set up

- Xcode 26+ (the design layer uses the iOS 26 `glassEffect` symbol)
- iOS 17.0+ runtime target

Open `Tabs.xcodeproj` and run on a device or simulator. Vision OCR returns no
text on a blank simulator photo library, so test the screenshot path with a real
statement image or use the PDF path.

## Workflow

`main` stays linear, and changes land through pull requests — don't commit to
`main` directly.

1. Branch off `main`. Name it for the work: `fix/duplicate-detection`,
   `feat/csv-import`.
2. Make the change. Keep it focused — one concern per PR.
3. Run the tests (see below). Green before you open the PR.
4. Open a PR against `main`. Describe what changed and why, and link any issue.
5. Merge with **Squash** or **Rebase** (merge commits are disabled, so history
   stays linear). The branch is deleted automatically on merge.

Keep PRs small. A 200-line PR gets a real review; a 2,000-line one gets a
rubber stamp, and that helps no one.

## Building and testing

Common tasks are wrapped in the `Makefile` (`make help` lists them):

```
make test          # run the unit suite on a simulator
make run           # build, install, and launch on a simulator
make run SEED=1    # same, but preload demo data
```

For shipping a beta to TestFlight, see [docs/RELEASING.md](docs/RELEASING.md).

## Tests

Unit coverage lives in `TabsTests/`, with the detector logic in
`RecurringChargeDetectorTests.swift`. Run them in Xcode (Cmd-U) or `make test`.

If you touch detection — amount clustering, cadence inference, the money regex,
the keyword catalog — add or update a test that proves the behavior. Detection
is the heart of the app and breaks in subtle ways without coverage.

## Code style

Match the code already in the file you're editing. Beyond that:

- Add new brands in one place: `SubscriptionKeywordCatalog.defaultRules`.
- Keep OCR/PDF/parsing work off the main thread.
- Use the semantic colors, type ramp, and spacing scales in
  `DesignSystem/Theme.swift` rather than hardcoded values.
- Views go in `Views/`, persistence models in `Models/`, logic in `Services/`.
  Follow the layout in the README.

## Commits

Short, present-tense subject lines that say what changed. Body only when the
"why" isn't obvious from the diff. Squash noise before you open the PR.

## Reporting bugs

Open an issue with steps to reproduce, what you expected, and what happened.
For detection bugs, a sample statement line (with real account numbers and
amounts redacted) is worth more than a paragraph of description.
