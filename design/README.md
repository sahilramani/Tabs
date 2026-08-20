# Design sources

The `.dc.html` files here are the design sources the published pages in `docs/`
were exported from. They are kept as a **read-only record of the design**, not
as something this repo can build.

They are Claude Design exports: a `<x-dc>` custom element driven by a runtime
(`support.js`) that they each load with a `<script>` tag. That runtime is not
vendored here — it is third-party generated code that carries no license or
copyright notice of its own, and this repo's MIT `LICENSE` should not be read
as covering it. So **the `.dc.html` files will not render as-is**; opening one
gives a blank page and a 404 for the missing script. Reproducing them needs
the tool they were authored in.

None of this affects the site. `docs/` holds flattened, self-contained HTML
with no dependency on any of the above, and that is what GitHub Pages serves.

| Source | Published as |
|---|---|
| `Tabs Landing.dc.html` | `docs/index.html` |
| `Tabs Getting Started.dc.html` | `docs/getting-started.html` |
| `Tabs Usage.dc.html` | `docs/usage.html` |
| `Tabs Contact.dc.html` | `docs/contact.html` |
| `Tabs App Screens.dc.html` | — (app design reference, not a web page) |

They live outside `docs/` on purpose: `docs/` is the GitHub Pages root, so
anything in it is published, and these are not pages to serve.

**Edit the published HTML in `docs/` directly.** It is plain,
self-contained HTML — the sources here cannot be re-exported without the
original tool, so treat them as a snapshot of the design at export time, not
as the thing you change. Expect them to drift from `docs/` over time; where
they disagree, `docs/` is what ships.

## app-screens

`app-screens-handoff.md` and `screenshots/` are the design handoff for the four
core app screens (Home, Import sheet, Review detections, Subscription detail),
implemented in SwiftUI in `Tabs/Views/`.

`screenshots/` are **design renders, not app captures** — the real captures of
the shipped app live in `docs/screenshots/`.

The shipped app deliberately diverges from the handoff in places — e.g. the
handoff's "Delete → confirmation, permanent" is implemented as a restorable
Trash, which the app already had. Where they disagree, the app is the source
of truth.
