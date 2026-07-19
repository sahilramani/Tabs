# Design sources

The `.dc.html` files here are the design sources the published pages in `docs/`
were exported from. They render through `support.js` (a generated runtime — do
not edit it by hand) and use a `<x-dc>` custom element, so they are not
directly servable as the site; `docs/` holds the flattened output.

| Source | Published as |
|---|---|
| `Tabs Landing.dc.html` | `docs/index.html` |
| `Tabs Getting Started.dc.html` | `docs/getting-started.html` |
| `Tabs Usage.dc.html` | `docs/usage.html` |
| `Tabs Contact.dc.html` | `docs/contact.html` |
| `Tabs App Screens.dc.html` | — (app design reference, not a web page) |

They live outside `docs/` on purpose: `docs/` is the GitHub Pages root, so
anything in it is published. Keeping the sources here avoids serving a second
copy of every page plus an unused 54 KB runtime.

If you change a page, change the source here and re-export to `docs/` so the
two do not drift. `Tabs Usage.dc.html` resolves `screenshots/` against this
directory, so it previews standalone against the mockups below.

## app-screens

`app-screens-handoff.md` and `screenshots/` are the design handoff for the four
core app screens (Home, Import sheet, Review detections, Subscription detail),
implemented in SwiftUI in `Tabs/Views/`.

`screenshots/` are **design renders, not app captures** — the real captures of
the shipped app live in `docs/screenshots/`.
