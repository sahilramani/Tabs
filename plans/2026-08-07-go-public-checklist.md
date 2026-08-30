# Go-public checklist

Everything repo-side is done. Staged and verified while private:
Discussions enabled, homepage URL, topics, CoC, SECURITY/PRIVACY policies,
the unlicensed design runtime removed, and `v0.1.0` + `v0.2.0` tagged.
0.2.0 is the redesign — cut it before going public so the latest release
matches the screenshots on the site.

**Done 2026-08-30.** All of it. Kept as a record.

One surprise worth remembering: the user-site custom domain rewrites every
project page, so this site is canonically at https://www.sahilramani.com/Tabs/
and `sahilramani.github.io/Tabs/` only redirects there. The absolute `og:`
URLs had to be repointed, since scrapers generally don't follow redirects
for `og:image`.

- [x] **Flip visibility**: `gh repo edit sahilramani/Tabs --visibility public`
      (or Settings → Danger Zone). Everything in the history becomes public —
      it has been audited, but this is the point of no return.
- [x] **Enable Pages**: Settings → Pages → Deploy from a branch → `main`,
      `/docs`. Or:
      `gh api -X POST repos/sahilramani/Tabs/pages -f 'source[branch]=main' -f 'source[path]=/docs'`
- [x] **Enable private vulnerability reporting** (SECURITY.md links to it):
      `gh api -X PUT repos/sahilramani/Tabs/private-vulnerability-reporting`
      (404s while the repo is private — that's why it's on this list.)
- [x] **Verify the live site**: all four pages render at
      https://www.sahilramani.com/Tabs/, screenshots load, the Discussions
      card on contact.html resolves, `/RELEASING.md` now 404s (it moved out
      of the webroot — a 404 there is correct).
- [x] **Verify the share card**: paste the site URL into a scraper debugger
      (e.g. opengraph.xyz) and check the social image resolves.
- [x] **Optional**: publish a GitHub Release for `v0.2.0` (and `v0.1.0`) with
      the matching CHANGELOG notes; the tag pages resolve without it.

Separate from going public — shipping the build itself needs a paid Apple
Developer account and your credentials, so it is not automated here:

- [x] **TestFlight**: `make beta` (step 4 of [RELEASING.md](../RELEASING.md)).
      Bump `CURRENT_PROJECT_VERSION` for each upload of the same marketing
      version.
