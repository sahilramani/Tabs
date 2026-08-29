# TestFlight checklist — 0.2.0, internal testing

Repo side is done: iPhone-only, portrait-locked, 0.2.0 tagged, signing
wired to `ASC_TEAM_ID`. Verified in the built binary — `UIDeviceFamily [1]`,
`CFBundleShortVersionString 0.2.0`, `ITSAppUsesNonExemptEncryption false`,
1024px app icon with no alpha.

Internal testing needs no Beta App Review and no hosted privacy-policy URL,
so none of this depends on the repo being public.

## On this Mac

- [ ] **Sign in**: Xcode → *Settings → Accounts* → add the Apple ID now
      enrolled in the Developer Program.
- [ ] **Create a distribution certificate**: same screen → *Manage
      Certificates…* → **+** → **Apple Distribution**. The only certificate
      currently in the keychain is an *Apple Development* one that expired
      2026-02-19, and development certs can't sign a TestFlight build.

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
      the URL at https://sahilramani.github.io/Tabs/.
- [ ] iPad and Mac Catalyst layouts. `TARGETED_DEVICE_FAMILY` and
      `SUPPORTS_MACCATALYST` are the switches; `Tabs/Tabs.entitlements`
      already carries the macOS sandbox keys for when Catalyst returns.
