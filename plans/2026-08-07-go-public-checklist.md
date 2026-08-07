# Go-public checklist

Everything repo-side is done (see the 2026-08-07 commits). Staged and
verified while private: Discussions enabled, homepage URL, topics, CoC,
SECURITY/PRIVACY policies, v0.1.0 tag pushed. What's left has to happen in
this order, because Pages and vulnerability reporting only exist on public
repos.

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
- [ ] **Optional**: publish a GitHub Release for `v0.1.0` with the CHANGELOG
      0.1.0 notes; the tag page already resolves without it.
