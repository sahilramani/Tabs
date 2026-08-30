# Privacy policy

**Tabs collects nothing.** Everything the app does happens on your device.

Also published at <https://www.sahilramani.com/Tabs/privacy.html>. The two mirror each other; edit both, or neither.

## What the app processes

- **Screenshots you pick** are OCR'd on-device with Apple's Vision framework.
- **PDF statements you pick** are read on-device with Apple's PDFKit.
- **Detected subscriptions** (name, price, billing cycle, and the statement
  lines that support them) are stored in a local SwiftData database inside the
  app's sandbox.
- **Renewal reminders** are local notifications scheduled on the device.

## What leaves your device

Nothing. The app has no networking layer — no analytics, no crash reporting,
no telemetry, no third-party SDKs, no accounts. The source is public, so this
is verifiable: there are no `URLSession`/network imports in the app target,
and the [privacy manifest](Tabs/PrivacyInfo.xcprivacy) declares no data
collection and no tracking.

## Data retention and deletion

Your data lives only in the app's local store. Deleting a subscription moves
it to the in-app Trash; emptying the Trash removes it permanently. Deleting
the app removes everything.

## Permissions

- **Photo library** — read-only picker, only when you choose "Scan a
  screenshot". The app sees only the images you select.
- **Notifications** — optional, for renewal reminders. Denying it disables
  reminders and nothing else.

## Changes

Any change to this policy will appear in this file's git history — the policy
is versioned with the code that implements it.
