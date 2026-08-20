# Go-public checklist

Everything repo-side is done. Staged and verified while private:
Discussions enabled, homepage URL, topics, CoC, SECURITY/PRIVACY policies,
the unlicensed design runtime removed, and `v0.1.0` + `v0.2.0` tagged.
0.2.0 is the redesign — cut it before going public so the latest release
matches the screenshots on the site.

What's left has to happen in this order, because Pages and vulnerability
reporting only exist on public repos.

- [ ] **Flip visibility**: `gh repo edit sahilramani/Tabs --visibility public`
      (or Settings → Danger Zone). Everything in the history becomes public —
      it has been audited, but this is the point of no return.
- [ ] **Enable Pages**: Settings → Pages → Deploy from a branch → `main`,
      `/docs`. Or:
      `gh api -X POST repos/sahilramani/Tabs/pages -f 'source[branch]=main' -f 'source[path]=/docs'`
- [ ] **Enable private vulnerability reporting** (SECURITY.md links to it):
      `gh api -X PUT repos/sahilramani/Tabs/private-vulnerability-reporting`
      (404s while the repo is private — that's why it's on this list.)
- [ ] **Verify the live site**: all four pages render at
      https://sahilramani.github.io/Tabs/, screenshots load, the Discussions
      card on contact.html resolves, `/RELEASING.md` now 404s (it moved out
      of the webroot — a 404 there is correct).
- [ ] **Verify the share card**: paste the site URL into a scraper debugger
      (e.g. opengraph.xyz) and check the social image resolves.
- [ ] **Optional**: publish a GitHub Release for `v0.2.0` (and `v0.1.0`) with
      the matching CHANGELOG notes; the tag pages resolve without it.

Separate from going public — shipping the build itself needs a paid Apple
Developer account and your credentials, so it is not automated here:

- [ ] **TestFlight**: `make beta` (step 4 of [RELEASING.md](../RELEASING.md)).
      Bump `CURRENT_PROJECT_VERSION` for each upload of the same marketing
      version.
