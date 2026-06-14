# Sample statements

Synthetic, privacy-safe statement fixtures for demoing and testing Tabs's
import flow. Every name, account number, and amount is fictional.

- `statement.html` — the source layout.
- `generate-statement.sh` — renders it to a text-selectable PDF via headless
  Chrome (PDFKit needs real text, not a scanned image).
- `sample-statement.pdf` — the generated fixture. One month of charges mixing
  recognizable subscriptions (Netflix, Spotify, Hulu, iCloud, Adobe, Amazon
  Prime, YouTube Premium, Disney+, Comcast, Planet Fitness) with noise
  (groceries, gas, marketplace, restaurants) so detection has something to
  separate.

Regenerate after editing the HTML:

```sh
./samples/generate-statement.sh
```

Use it via the app's **Import PDF** button, or drag it onto the app window.
