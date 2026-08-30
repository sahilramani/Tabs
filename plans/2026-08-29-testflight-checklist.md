# TestFlight checklist — 0.2.0, internal testing

Repo side is done: iPhone-only, portrait-locked, 0.2.0 tagged, signing
wired to `ASC_TEAM_ID` (`2U76H9X5Z9`). Verified in the built binary — `UIDeviceFamily [1]`,
`CFBundleShortVersionString 0.2.0`, `ITSAppUsesNonExemptEncryption false`,
1024px app icon with no alpha.

Internal testing needs no Beta App Review and no hosted privacy-policy URL,
so none of this depends on the repo being public.

## On this Mac

- [x] **Sign in** — done. Team `2U76H9X5Z9` (Sahil Ramani) is active, with a
      valid *Apple Development* certificate (to 2027-06-11) and an Xcode-managed
      development profile for `com.sahilramani.tabs` covering 2 devices.
      `make device` produces a correctly signed build.
- [ ] **Create a distribution certificate**: Xcode → *Settings → Accounts* →
      *Manage Certificates…* → **+** → **Apple Distribution**. Development certs
      cannot sign a TestFlight build. `make archive` will also create one
      automatically via `-allowProvisioningUpdates`.

## In App Store Connect

- [ ] **App record**: *Apps* → **+** → New App. iOS, bundle id
      `com.sahilramani.tabs`, name "Tabs", SKU anything.
- [ ] **App Privacy**: answer **Data Not Collected**. Required before a build
      can be distributed. Backed by `Tabs/PrivacyInfo.xcprivacy` and
      [PRIVACY.md](../PRIVACY.md).
- [ ] **API key**: *Users and Access → Integrations → App Store Connect API*
      → generate with **App Manager** access. The `.p8` downloads once — put
      it in `~/.appstoreconnect/private_keys/`. Note the Key ID and Issuer ID.

## Upload

```sh
export ASC_TEAM_ID=<Team ID>       # developer.apple.com/account → Membership
export ASC_KEY_ID=<Key ID>
export ASC_ISSUER_ID=<Issuer ID>
make beta
```

- [ ] `make beta` (archive → export → upload). Build number is stamped from
      the timestamp, so repeat uploads never collide.
- [ ] Once processing finishes, add yourself to an **Internal Testing** group
      in the app's *TestFlight* tab and install via the TestFlight app.

Builds expire 90 days after upload.

## Later

- [ ] External testers — needs Beta App Review plus a public privacy-policy
      URL, so flip the repo public and enable Pages first
      ([go-public checklist](2026-08-07-go-public-checklist.md)); then point
      the URL at https://www.sahilramani.com/Tabs/.
- [ ] iPad and Mac Catalyst layouts. `TARGETED_DEVICE_FAMILY` and
      `SUPPORTS_MACCATALYST` are the switches; `Tabs/Tabs.entitlements`
      already carries the macOS sandbox keys for when Catalyst returns.
