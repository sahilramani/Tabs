# Releasing Tabs

How to test Tabs locally and ship a beta to TestFlight. Local testing needs
only Xcode. Everything past "Archive" needs a paid Apple Developer account.

All commands are wrapped in the [Makefile](Makefile) — run `make help` to
list them.

## Local testing (no account needed)

```sh
make test          # run the unit suite on a simulator
make run           # build + install + launch on a simulator
make run SEED=1    # same, but preload demo subscriptions
```

`make run SEED=1` passes `--seed-demo`, which inserts a sample dataset (Debug
only) so you can exercise the UI without importing a real statement.

Add `SCREEN=import`, `SCREEN=review`, or `SCREEN=detail` to open one of those
screens on launch instead of the home list — handy for refreshing the
screenshots in `docs/screenshots/` without tapping through the app:

```sh
make run SEED=1 SCREEN=import
```

To test on your own iPhone, plug it in and either Run from Xcode, or:

```sh
make device                       # build a device binary
xcrun devicectl list devices      # find your device UDID
xcrun devicectl device install app --device <UDID> \
  build/DerivedData/Build/Products/Debug-iphoneos/Tabs.app
```

With a free Apple ID the device build is signed for 7 days; with the paid
account it lasts a year.

## One-time setup for TestFlight

1. **Enroll** in the Apple Developer Program ($99/yr).
2. **Signing**: open `Tabs.xcodeproj` → target *Tabs* → *Signing & Capabilities*
   → check *Automatically manage signing* and pick your Team. (The macOS
   sandbox entitlements are ignored on iOS; no other capabilities are needed.)
3. **App record**: in [App Store Connect](https://appstoreconnect.apple.com) →
   *Apps* → **+** → New App. Platform iOS, bundle id `com.sahilramani.tabs`,
   name "Tabs".
4. **App Privacy**: in the app record, fill the privacy questionnaire as
   **Data Not Collected** (the app has no networking and collects nothing —
   see `Tabs/PrivacyInfo.xcprivacy`). Required before TestFlight.
5. **Upload API key**: App Store Connect → *Users and Access* → *Integrations*
   → *App Store Connect API* → generate a key with *App Manager* access.
   Download `AuthKey_<KEYID>.p8` (one-time) and move it to
   `~/.appstoreconnect/private_keys/`. Note the **Key ID** and **Issuer ID**.

## Cutting a beta build

```sh
export ASC_KEY_ID=<your Key ID>
export ASC_ISSUER_ID=<your Issuer ID>
make beta
```

`make beta` archives, exports an `.ipa` via [ExportOptions.plist](ExportOptions.plist),
and uploads it. The build number is stamped from the current timestamp, so
every upload is unique without editing the project. Override with
`make beta BUILD=42` if you want a specific number.

After upload the build shows up in App Store Connect → your app → *TestFlight*
once processing finishes (usually a few minutes).

> No-CLI alternative: `make archive` then open the archive in Xcode's Organizer
> (*Window → Organizer*) and use *Distribute App*. Or upload the exported
> `.ipa` with Apple's **Transporter** app.

## Inviting testers

**Internal** (up to 100, no review, instant): add the people as Users in App
Store Connect, then add them to an Internal Testing group. Good for yourself
and a few trusted testers.

**External** (up to 10,000, public link possible): create an External group,
add a "what to test" note and contact email. The first build goes through a
light **Beta App Review**; subsequent builds usually clear quickly.

Testers install the **TestFlight** app and open the invite link or redeem the
code. Builds expire **90 days** after upload — push a new one to keep testing.

## Versioning and changelog

Tabs uses [Semantic Versioning](https://semver.org). It is pre-1.0, so it
ships as an **alpha** — the in-app badge and version footer come from
`AppInfo.stage`; clear that string when the app reaches a stable release.

- **Marketing version** (`MARKETING_VERSION`, currently `0.2.0`) — the
  user-facing version. Bump it in the target's build settings for a release
  (`0.1.0` → `0.2.0` for new features, `→ 1.0.0` to leave alpha).
- **Build number** (`CURRENT_PROJECT_VERSION`) — stamped per upload by
  `make beta`. Must increase for every build of the same marketing version.

Every release:

1. Move the `Unreleased` notes in [CHANGELOG.md](CHANGELOG.md) under a new
   version heading with today's date.
2. Bump `MARKETING_VERSION` to match.
3. Tag the commit: `git tag vX.Y.Z && git push --tags`.
4. `make beta`.

## Notes

- Export compliance is pre-answered: `ITSAppUsesNonExemptEncryption = NO` in
  the build settings, so uploads don't prompt for it.
- Prefer `fastlane` later? A `beta` lane maps cleanly onto `make beta` —
  `build_app` + `upload_to_testflight` with the same API key. Not added here to
  keep the toolchain dependency-free.
